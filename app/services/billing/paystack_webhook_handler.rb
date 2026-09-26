# Synkra Chat billing: processes verified Paystack webhook events and
# updates the local SynkraSubscription accordingly. Signature
# verification happens in the controller before this is ever called -
# this class trusts its input completely, so it must never be invoked
# directly from anywhere that hasn't already verified the signature.
class Billing::PaystackWebhookHandler
  def initialize(event)
    @event = event
    @data = event['data'] || {}
  end

  def process!
    case @event['event']
    when 'charge.success'
      handle_charge_success
    when 'subscription.create'
      handle_subscription_create
    when 'invoice.payment_failed'
      handle_payment_failed
    when 'subscription.disable', 'subscription.not_renew'
      handle_subscription_disabled
    else
      Rails.logger.info "[SynkraBilling] Unhandled Paystack event: #{@event['event']}"
    end
  end

  private

  def find_subscription
    account_id = @data.dig('metadata', 'synkra_account_id') || @data.dig('metadata', 'account_id')
    return find_subscription_by_customer if account_id.blank?

    SynkraSubscription.find_by(account_id: account_id)
  end

  # Paystack's own recurring charges (renewals) don't carry the
  # metadata we attach at checkout, so fall back to the Paystack
  # customer we stored from the first payment.
  def find_subscription_by_customer
    customer_code = @data.dig('customer', 'customer_code')
    return nil if customer_code.blank?

    SynkraSubscription.find_by(paystack_customer_code: customer_code)
  end

  def handle_charge_success
    # Message add-on, extra-seat, and extra-storage purchases are
    # one-time/on-demand charges, NOT a plan renewal - they must never
    # fall through into the subscription lifecycle logic below
    # (mark_active!, start_new_period!, apply_pending_plan_change!
    # would all be wrong here). Extra seats and extra storage
    # specifically: both complete synchronously via
    # charge_authorization's direct API response - this webhook for
    # that same charge is a pure no-op, not a second completion step.
    purchase_type = @data.dig('metadata', 'purchase_type')
    if purchase_type == 'message_addon'
      handle_message_addon_purchase
      return
    elsif %w[extra_seats extra_storage].include?(purchase_type)
      return
    end

    subscription = find_subscription
    return if subscription.nil?

    capture_authorization(subscription)
    capture_customer(subscription)

    # A successful charge always clears any past-due/restricted state,
    # whether it was the very first payment or a recovery payment.
    subscription.mark_active!

    activate_plan_from_checkout(subscription)

    if subscription.pending_plan.present?
      swap_paystack_plan_if_pending!(subscription)
    end

    subscription.start_new_period!
    subscription.apply_pending_plan_change!
    bill_extra_seats_for_renewal(subscription)
    bill_extra_storage_for_renewal(subscription)
  end

  # See SynkraSubscription#bill_extra_seats_for_renewal! for the actual
  # charge and its idempotency guard - this just supplies the renewal
  # charge's own Paystack reference as the idempotency key. Called
  # AFTER start_new_period!/apply_pending_plan_change! above, so this
  # never blocks or delays the plan renewal itself succeeding, even if
  # the extra-seat charge fails (that method fails open - see its
  # comment).
  def bill_extra_seats_for_renewal(subscription)
    subscription.bill_extra_seats_for_renewal!(@data['reference'])
  end

  # See SynkraSubscription#bill_extra_storage_for_renewal! - same
  # idempotency/fail-open reasoning as bill_extra_seats_for_renewal
  # above. Storage moved to the same pre-purchased-quantity model as
  # extra seats on 16 Sep 2026 (previously: automatic metered overage
  # billing with no purchase step - see that migration's comment).
  def bill_extra_storage_for_renewal(subscription)
    subscription.bill_extra_storage_for_renewal!(@data['reference'])
  end

  # Credits MessageAddonPurchase#units onto the subscription's
  # purchased_message_credits balance - see
  # SynkraSubscription#consume_purchased_message_credit_if_over_plan_allowance!
  # for how it's spent. Idempotent: Paystack can and does redeliver
  # webhooks, and completed is a one-way state, so a duplicate
  # charge.success for the same reference is a no-op rather than
  # double-crediting.
  def handle_message_addon_purchase
    reference = @data['reference']
    return if reference.blank?

    purchase = MessageAddonPurchase.find_by(paystack_reference: reference)
    return if purchase.nil? || purchase.status == 'completed'

    ActiveRecord::Base.transaction do
      purchase.update!(status: 'completed')
      subscription = SynkraSubscription.find_by(account_id: purchase.account_id)
      subscription&.increment!(:purchased_message_credits, purchase.units)
    end
  end

  # First payment from checkout: the plan (and the discount programme it
  # was priced under) travel in the transaction metadata we set in
  # SubscriptionsController#checkout. Nothing else flips a Free account
  # to the plan it just paid for. Renewals carry no such metadata and
  # are a no-op here. Upgrades go through change_plan! so they take
  # effect immediately and sync to Flow like any other upgrade.
  def activate_plan_from_checkout(subscription)
    plan = @data.dig('metadata', 'plan').to_s
    return if plan.blank? || plan == 'free' || !SynkraPlan.valid?(plan)

    # Only ever moves UP. Same plan = a redelivered webhook (or a
    # renewal that happens to carry metadata); lower = not a checkout
    # path. Both must not touch anything - change_plan! with an equal
    # plan would schedule a pointless Paystack plan swap.
    order = SynkraPlan::PLANS.keys
    return unless order.index(plan) > order.index(subscription.plan)

    programme = @data.dig('metadata', 'pricing_programme').to_s
    programme = nil unless SynkraPlan::PROGRAMME_PLANS.key?(programme)

    subscription.change_plan!(plan)
    subscription.update!(pricing_programme: programme)
  end

  def capture_customer(subscription)
    customer_code = @data.dig('customer', 'customer_code')
    return if customer_code.blank? || subscription.paystack_customer_code == customer_code

    subscription.update!(paystack_customer_code: customer_code)
  end

  # Stores the card/direct-debit authorization from this charge so a
  # future plan downgrade can create a replacement Paystack
  # subscription without sending the customer through checkout again.
  # Paystack sends this on every successful charge, not just the
  # first, so this just keeps the most recent one on file.
  def capture_authorization(subscription)
    authorization_code = @data.dig('authorization', 'authorization_code')
    return if authorization_code.blank?

    subscription.update!(paystack_authorization_code: authorization_code)
  end

  # The local plan (SynkraSubscription#plan) already flips correctly
  # on its own via apply_pending_plan_change! below - but on its own,
  # that ONLY updates our database. Paystack's own subscription object
  # still references the OLD, more expensive plan, and would keep
  # charging that amount every cycle forever unless we actually swap
  # it here. This is called before apply_pending_plan_change! so the
  # local plan hasn't flipped yet when we read pending_plan/plan.
  def swap_paystack_plan_if_pending!(subscription)
    service = Billing::PaystackService.new
    new_plan_key = subscription.pending_plan
    # Keep the discount only while it's still valid: an expired
    # programme never carries over onto the new plan.
    programme = SynkraProgrammeVerification.best_active_programme(subscription.account_id)
    new_plan_code = SynkraPlan.for_programme(new_plan_key, programme)[:paystack_plan_code]

    if subscription.paystack_subscription_code.present?
      service.cancel_subscription(
        subscription_code: subscription.paystack_subscription_code,
        email_token: subscription.paystack_email_token
      )
    end

    if new_plan_code.blank?
      # Downgrading to Free: cancelling the old Paystack subscription
      # above is the whole job - there's nothing to create, and the
      # customer is never charged again until they choose a paid plan.
      subscription.update!(paystack_subscription_code: nil, paystack_email_token: nil, pricing_programme: nil)
      return
    end

    if subscription.paystack_authorization_code.blank?
      Rails.logger.error "[SynkraBilling] Can't sync downgrade to Paystack for subscription #{subscription.id}: no stored authorization"
      return
    end

    result = service.create_subscription(
      customer_code: subscription.paystack_customer_code,
      plan_code: new_plan_code,
      authorization_code: subscription.paystack_authorization_code,
      # Deferred to the upcoming period boundary (about to be set by
      # start_new_period! right after this returns) so the new,
      # cheaper subscription's first charge never overlaps with the
      # charge that just landed for the old plan's final cycle.
      start_date: 1.month.from_now
    )

    if result.success?
      subscription.update!(
        paystack_subscription_code: result.data['subscription_code'],
        paystack_email_token: result.data['email_token'],
        pricing_programme: programme
      )
    else
      Rails.logger.error "[SynkraBilling] Failed to create replacement Paystack subscription for downgrade (subscription #{subscription.id}): #{result.error}"
      # Local plan still gets flipped by apply_pending_plan_change!
      # regardless - leaving the account on the OLD plan locally after
      # we've already cancelled its Paystack subscription would be
      # worse (Pro-level limits shown with no active billing behind
      # them at all). This failure needs manual follow-up, which is
      # what the error log above is for.
    end
  end

  def handle_subscription_create
    subscription = find_subscription
    return if subscription.nil?

    subscription.update!(
      paystack_subscription_code: @data['subscription_code'],
      paystack_email_token: @data['email_token'],
      paystack_customer_code: @data.dig('customer', 'customer_code')
    )
  end

  def handle_payment_failed
    subscription = find_subscription
    return if subscription.nil?

    was_already_past_due = subscription.past_due?
    subscription.mark_past_due!
    Billing::NotificationMailer.payment_failed(subscription: subscription).deliver_later unless was_already_past_due
    # Actually moving from past_due -> restricted happens on a
    # scheduled job (Billing::RestrictOverdueSubscriptionsJob) once the
    # grace period elapses, not immediately here - a single failed
    # charge should never instantly cut anyone off.
  end

  def handle_subscription_disabled
    subscription = find_subscription
    return if subscription.nil?

    subscription.update!(status: 'cancelled', paystack_subscription_code: nil)
  end
end
