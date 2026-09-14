# Synkra Chat's own billing subscription - one per account. Deliberately
# separate from Chatwoot's own billing concepts. Flow itself is a
# separate product with its own billing (no cross-subsidy of the
# Rand-value Paystack subscription below), but as of the "Automations"
# bridge (12 Sep 2026) this account's usage of Flow's AI-ops/email
# credits is NOT a separate Flow subscription the business holds - it's
# a single shared balance on an auto-provisioned Flow shadow user this
# account never sees or logs into. See Automations::FlowClient and
# synkra-core/services/chat_shadow.py for the full design.
class SynkraSubscription < ApplicationRecord
  STATUSES = %w[active past_due restricted cancelled].freeze
  # How long a failed payment gets to resolve (retries + reminders)
  # before outbound/paid features actually get restricted. Inbound
  # customer messaging is NEVER restricted, at any status.
  GRACE_PERIOD = 5.days

  belongs_to :account

  encrypts :flow_api_key if Chatwoot.encryption_configured?

  validates :plan, inclusion: { in: SynkraPlan.names }
  validates :status, inclusion: { in: STATUSES }

  before_validation :set_default_period, on: :create

  def plan_config
    SynkraPlan.find(plan)
  end

  # The plan's own staff_limit plus any purchased extra seats
  # (SynkraPlan::EXTRA_SEAT_PRICE_ZAR/seat/month) - see
  # AccountUser#ensure_within_synkra_seat_limit, which is the actual
  # enforcement point.
  def effective_seat_limit
    plan_config[:staff_limit].to_i + purchased_extra_seats
  end

  # Grants N extra seats immediately, on top of whatever is already
  # purchased - NO CHARGE at the moment of purchase. The first real
  # charge happens automatically at the account's next plan renewal,
  # via bill_extra_seats_for_renewal! below (already built, already
  # idempotent). Decided 13 Sep 2026 (Refilwe, on Claude's
  # recommendation) over prorating the first charge: day-based
  # proration is the "more correct" approach most SaaS platforms use,
  # but adds real complexity (partial-amount math, period-boundary
  # edge cases) for a small amount (R69/seat). This way can never
  # double-charge, which proration risks getting subtly wrong without
  # live Paystack testing. The accepted tradeoff: a business that buys
  # seats right after a renewal gets that first month free (bounded,
  # one-time per purchase, not a recurring loss).
  def purchase_extra_seats!(quantity)
    return invalid_seat_purchase_result('Quantity must be positive') if quantity.to_i <= 0
    return invalid_seat_purchase_result('No card on file - complete a plan checkout first') if paystack_authorization_code.blank?

    increment!(:purchased_extra_seats, quantity.to_i)
    Billing::PaystackService::Result.new(success?: true, data: { 'granted_seats' => quantity.to_i })
  end

  # The recurring side: re-bills the FULL current purchased_extra_seats
  # count (not an increment) every plan renewal, so the charge stays
  # aligned to the same billing cycle as the base plan price. Called
  # from Billing::PaystackWebhookHandler#bill_extra_seats_for_renewal
  # as part of handling the plan's own charge.success renewal event -
  # never called directly from a controller.
  #
  # reference is the RENEWAL charge's own Paystack transaction
  # reference (not this seat charge's) - it's the idempotency key.
  # Paystack redelivers webhooks on retry, and a redelivered webhook
  # for the same renewal must NEVER charge the card twice for seats -
  # unlike start_new_period!, which merely resets a clock and is
  # harmless to re-run, charge_authorization moves real money.
  def bill_extra_seats_for_renewal!(reference)
    return if purchased_extra_seats <= 0
    return if reference.blank? # can't safely guarantee idempotency without one - skip rather than risk a double charge
    return if extra_seats_billed_for_reference == reference # already billed for this exact renewal event

    result = charge_for_extra_seats(purchased_extra_seats, purchase_type_metadata: 'extra_seats')
    if result.success?
      update!(extra_seats_billed_for_reference: reference)
    else
      # Fails open, matching this codebase's established philosophy
      # (Message/AccountUser billing enforcement) - a failed recurring
      # seat charge must never lock the business out of the seats they
      # already have. There is currently no dunning/retry mechanism
      # specific to extra seats (unlike the base plan, which has
      # Billing::RestrictOverdueSubscriptionsJob) - a permanently
      # failing card silently keeps granting the seats. Worth revisiting
      # if this proves to matter in practice.
      Rails.logger.error("[SynkraBilling] Extra-seat renewal charge failed for account #{account_id}: #{result.error}")
    end
    result
  end

  def active?
    status == 'active'
  end

  def restricted?
    status == 'restricted'
  end

  def past_due?
    status == 'past_due'
  end

  def cancelled?
    status == 'cancelled'
  end

  # Outbound/business-initiated messaging and paid features are blocked
  # once actually restricted - NOT merely past_due (that's the grace
  # period, during which everything keeps working while payment retries
  # run in the background).
  def outbound_blocked?
    restricted? || cancelled?
  end

  # --- Usage / allowance ---

  def business_initiated_messages_used(period_start = current_period_start)
    return 0 if period_start.blank?

    account.synkra_usage_events
           .where(resource_type: 'business_initiated_message')
           .where('occurred_at >= ?', period_start)
           .sum(:quantity).to_i
  end

  def business_initiated_message_allowance
    plan_config[:business_initiated_message_allowance]
  end

  def usage_fraction
    allowance = business_initiated_message_allowance
    return 0.0 if allowance.to_i <= 0

    [business_initiated_messages_used.to_f / allowance, 1.0].min
  end

  # The plan's own period allowance only - deliberately NOT including
  # purchased_message_credits. Usage-warning emails (next_unnotified_threshold
  # below) are about "you're approaching your plan's included amount",
  # which stays meaningful regardless of whether a safety-net add-on
  # balance exists. Message#enforce_synkra_billing_restriction uses the
  # separate allowance_exhausted? below (which DOES consider purchased
  # credits) to decide whether to actually block sending.
  def plan_allowance_exhausted?
    business_initiated_messages_used >= business_initiated_message_allowance
  end

  # True only once there is genuinely nothing left to send with - the
  # plan's period allowance AND any purchased add-on credit
  # (Billing::MessageAddonPack) are both exhausted. This is what
  # actually blocks sending; plan_allowance_exhausted? alone does not.
  def allowance_exhausted?
    plan_allowance_exhausted? && purchased_message_credits <= 0
  end

  # Draws down the purchased add-on balance by one, but ONLY once the
  # plan's own period allowance is used up - a business should never
  # burn a paid-for add-on credit while they still have free plan
  # allowance left. Call this after a message is confirmed sent (see
  # Message#record_synkra_usage_event), not before - it must reflect
  # the allowance state at the moment the message actually went
  # through, not a pre-check.
  def consume_purchased_message_credit_if_over_plan_allowance!
    return unless plan_allowance_exhausted?
    return if purchased_message_credits <= 0

    decrement!(:purchased_message_credits)
  end

  # Returns the threshold (0.7/0.9/1.0) that should trigger a
  # notification right now, or nil if nothing new has been crossed
  # since the last one we sent. Resets naturally each period since
  # last_usage_warning_threshold is cleared on renewal.
  def next_unnotified_threshold
    fraction = usage_fraction
    already_notified = last_usage_warning_threshold.to_f
    candidate = SynkraPlan::WARNING_THRESHOLDS.select { |t| fraction >= t && t > already_notified }.max
    candidate
  end

  def mark_warning_sent!(threshold)
    update!(last_usage_warning_threshold: threshold)
  end

  def start_new_period!
    update!(
      current_period_start: Time.current,
      current_period_end: 1.month.from_now,
      last_usage_warning_threshold: nil
    )
  end

  # --- State transitions ---
  # These only change local state - the actual Paystack API calls
  # (creating/cancelling a subscription on Paystack's side) live in
  # Billing::PaystackService, which calls these after a successful
  # response, and Billing::PaystackWebhookHandler, which calls these
  # in response to Paystack's own webhook events.

  def mark_past_due!
    return unless active?

    update!(status: 'past_due', past_due_since: Time.current)
  end

  def mark_restricted!
    update!(status: 'restricted')
  end

  def mark_active!
    update!(status: 'active', past_due_since: nil)
  end

  def schedule_cancellation!
    update!(cancel_at_period_end: true)
  end

  def cancel_immediately!
    update!(status: 'cancelled', cancel_at_period_end: false)
  end

  # Upgrades take effect immediately (per spec); downgrades are only
  # ever scheduled for the end of the current period, never applied
  # right away - a customer who paid for Pro today should not lose
  # Pro capabilities today.
  def change_plan!(new_plan)
    return unless SynkraPlan.valid?(new_plan)

    if plan_rank(new_plan) > plan_rank(plan)
      update!(plan: new_plan, pending_plan: nil, plan_changed_at: Time.current)
      sync_flow_plan!(new_plan)
    else
      update!(pending_plan: new_plan)
    end
  end

  def apply_pending_plan_change!
    return if pending_plan.blank?

    new_plan = pending_plan
    update!(plan: new_plan, pending_plan: nil, plan_changed_at: Time.current)
    sync_flow_plan!(new_plan)
  end

  # Automations tab reads this - a thin passthrough to Flow's own
  # included/used numbers for this account's shadow user, never a
  # locally cached copy (see module comment: one shared balance).
  def automations_credits
    Automations::FlowClient.new(self).credits
  end

  # True when this subscription has a shadow client (flow_provisioned_at
  # present) but its Flow-side tier may not reflect the current plan -
  # either no sync has ever landed, or the plan changed after the last
  # one did. Automations::ReconcileFlowPlanJob uses this to self-heal a
  # SyncFlowPlanJob that exhausted its retries or never ran at all
  # (e.g. the process died before an enqueued job executed).
  def plan_sync_stale?
    return false if flow_provisioned_at.blank? || plan_changed_at.blank?

    flow_plan_synced_at.blank? || flow_plan_synced_at < plan_changed_at
  end

  private

  # Best-effort, async, and never allowed to raise into the caller -
  # a plan change must always succeed locally even if Flow is briefly
  # unreachable. Automations::SyncFlowPlanJob retries with backoff and
  # stamps flow_plan_synced_at on success; Automations::ReconcileFlowPlanJob
  # sweeps hourly for any subscription where that stamp is missing or
  # predates the last plan change, and retries - see plan_sync_stale?.
  def sync_flow_plan!(new_plan)
    Automations::SyncFlowPlanJob.perform_later(account_id, new_plan)
  end

  def plan_rank(plan_key)
    SynkraPlan.names.index(plan_key.to_s) || 0
  end

  # Shared by purchase_extra_seats! (charges for a quantity being
  # added) and bill_extra_seats_for_renewal! (charges for the full
  # current count, every period) - same underlying Paystack call,
  # different amount semantics, so kept as separate public methods
  # with this as their common plumbing.
  def charge_for_extra_seats(seat_count, purchase_type_metadata:)
    amount = seat_count * SynkraPlan::EXTRA_SEAT_PRICE_ZAR
    Billing::PaystackService.new.charge_authorization(
      email: account.administrators.first&.email || account.users.first&.email,
      amount_zar: amount,
      authorization_code: paystack_authorization_code,
      metadata: { synkra_account_id: account_id, purchase_type: purchase_type_metadata, quantity: seat_count }
    )
  end

  def invalid_seat_purchase_result(message)
    Billing::PaystackService::Result.new(success?: false, error: message)
  end

  def set_default_period
    return if current_period_start.present?

    self.current_period_start = Time.current
    self.current_period_end = 1.month.from_now
  end
end
