# Synkra Chat billing. Runs hourly (config/schedule.yml). Two jobs in
# one pass since both are cheap, simple sweeps over all subscriptions:
# 1. Move past_due subscriptions to restricted once their grace period
#    has elapsed (never faster than the promised grace period).
# 2. Send usage-warning emails when a NEW threshold (70/90/100%) is
#    crossed - next_unnotified_threshold already prevents repeats.
class Billing::RestrictOverdueSubscriptionsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    restrict_overdue_subscriptions
    send_usage_warnings
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
end
