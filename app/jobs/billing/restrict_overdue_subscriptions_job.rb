# Synkra Chat billing. Runs hourly (config/schedule.yml). Three
# sweeps in one pass since all are cheap, simple queries over all
# subscriptions:
# 1. Move past_due subscriptions to restricted once their grace period
#    has elapsed (never faster than the promised grace period).
# 2. Send usage-warning emails when a NEW threshold (70/90/100%) is
#    crossed - next_unnotified_threshold already prevents repeats.
# 3. Roll over Free-tier billing periods. Paid plans get this for free
#    via Paystack's own recurring billing (every charge.success calls
#    start_new_period! - see Billing::PaystackWebhookHandler) - but
#    Free accounts never go through checkout, so they never receive
#    ANY Paystack webhook, ever. Without this sweep, a Free account's
#    current_period_end is set once (or never - it isn't even
#    initialized at signup) and its usage allowance would never reset.
class Billing::RestrictOverdueSubscriptionsJob < ApplicationJob
  queue_as :scheduled_jobs

  # Accounts holding a paid plan for free, with no real Paystack
  # subscription behind them (comped internally - never charged, so
  # they'll never receive the charge.success webhook that normally
  # triggers a paid plan's period rollover/usage reset). Included in
  # rollover_free_tier_periods below so their usage still resets
  # monthly like a Free-tier account's does, while keeping their
  # actual plan's (higher) limits. Account 3 = Synkra Technologies
  # (hello@synkra.co.za), comped to Pro, 21 Sep 2026.
  COMPED_ACCOUNT_IDS = [3].freeze

  def perform
    restrict_overdue_subscriptions
    send_usage_warnings
    send_storage_warnings
    rollover_free_tier_periods
  end

  private

  def restrict_overdue_subscriptions
    SynkraSubscription.where(status: 'past_due')
                       .where('past_due_since <= ?', SynkraSubscription::GRACE_PERIOD.ago)
                       .find_each do |subscription|
      subscription.mark_restricted!
      Billing::NotificationMailer.account_restricted(subscription: subscription).deliver_later
    rescue StandardError => e
      Rails.logger.error "[SynkraBilling] Failed to restrict subscription #{subscription.id}: #{e.message}"
    end
  end

  def send_usage_warnings
    SynkraSubscription.where(status: %w[active past_due]).find_each do |subscription|
      threshold = subscription.next_unnotified_threshold
      next if threshold.nil?

      Billing::NotificationMailer.usage_warning(subscription: subscription, threshold: threshold).deliver_later
      subscription.mark_warning_sent!(threshold)
    rescue StandardError => e
      Rails.logger.error "[SynkraBilling] Failed to send usage warning for subscription #{subscription.id}: #{e.message}"
    end
  end

  # Separate sweep from send_usage_warnings above - storage doesn't
  # reset each period, so this can't share that method's per-period
  # logic, and needs its own column (last_storage_warning_threshold)
  # so a business sitting at 95% storage for months isn't re-notified
  # every single hourly run once already notified for that threshold.
  def send_storage_warnings
    SynkraSubscription.where(status: %w[active past_due]).find_each do |subscription|
      threshold = subscription.next_unnotified_storage_threshold
      next if threshold.nil?

      Billing::NotificationMailer.storage_warning(subscription: subscription, threshold: threshold).deliver_later
      subscription.mark_storage_warning_sent!(threshold)
    rescue StandardError => e
      Rails.logger.error "[SynkraBilling] Failed to send storage warning for subscription #{subscription.id}: #{e.message}"
    end
  end

  def rollover_free_tier_periods
    SynkraSubscription.where(status: 'active')
                       .where('plan = ? OR account_id IN (?)', 'free', COMPED_ACCOUNT_IDS)
                       .where('current_period_end IS NULL OR current_period_end <= ?', Time.current)
                       .find_each do |subscription|
      subscription.start_new_period!
    rescue StandardError => e
      Rails.logger.error "[SynkraBilling] Failed to roll over free-tier period for subscription #{subscription.id}: #{e.message}"
    end
  end
end
