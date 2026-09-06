# Synkra Chat's own billing subscription - one per account. Deliberately
# separate from Chatwoot's own billing concepts and from Flow's billing
# (no cross-subsidy between products; connecting Flow just consumes the
# business's own separate Flow subscription).
class SynkraSubscription < ApplicationRecord
  STATUSES = %w[active past_due restricted cancelled].freeze
  # How long a failed payment gets to resolve (retries + reminders)
  # before outbound/paid features actually get restricted. Inbound
  # customer messaging is NEVER restricted, at any status.
  GRACE_PERIOD = 5.days

  belongs_to :account

  validates :plan, inclusion: { in: SynkraPlan.names }
  validates :status, inclusion: { in: STATUSES }

  before_validation :set_default_period, on: :create

  def plan_config
    SynkraPlan.find(plan)
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

  def allowance_exhausted?
    business_initiated_messages_used >= business_initiated_message_allowance
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
      update!(plan: new_plan, pending_plan: nil)
    else
      update!(pending_plan: new_plan)
    end
  end

  def apply_pending_plan_change!
    return if pending_plan.blank?

    update!(plan: pending_plan, pending_plan: nil)
  end

  private

  def plan_rank(plan_key)
    SynkraPlan.names.index(plan_key.to_s) || 0
  end

  def set_default_period
    return if current_period_start.present?

    self.current_period_start = Time.current
    self.current_period_end = 1.month.from_now
  end
end
