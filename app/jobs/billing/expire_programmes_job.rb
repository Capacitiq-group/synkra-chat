# Discount programmes (Student / Community Access). Runs daily
# (config/schedule.yml):
# 1. Warns the account's admins 30 and 7 days before a programme they
#    are being charged under expires.
# 2. Expires lapsed verifications. If the account still qualifies for
#    another programme it is re-priced onto that; otherwise it moves to
#    the Free tier and its Paystack subscription is cancelled. It is
#    never silently charged the standard price.
class Billing::ExpireProgrammesJob < ApplicationJob
  queue_as :scheduled_jobs

  WARNING_DAYS = [30, 7].freeze

  def perform
    send_expiry_warnings
    expire_lapsed
  end

  private

  def send_expiry_warnings
    SynkraProgrammeVerification.where(status: 'verified').where('expires_at > ?', Time.current).find_each do |verification|
      days_left = ((verification.expires_at - Time.current) / 1.day).ceil
      threshold = WARNING_DAYS.select { |days| days_left <= days }.min
      next if threshold.nil?
      next if verification.expiry_warning_days.present? && verification.expiry_warning_days <= threshold

      subscription = SynkraSubscription.find_by(account_id: verification.account_id)
      next unless subscription&.pricing_programme == verification.programme

      Billing::ProgrammeMailer.expiry_warning(verification: verification, days_left: days_left).deliver_later
      verification.update!(expiry_warning_days: threshold)
    rescue StandardError => e
      Rails.logger.error "[SynkraProgramme] expiry warning failed for verification #{verification.id}: #{e.class}: #{e.message}"
    end
  end

  def expire_lapsed
    SynkraProgrammeVerification.where(status: 'verified').where('expires_at <= ?', Time.current).find_each do |verification|
      verification.update!(status: 'expired')
      lapse_account(verification)
    rescue StandardError => e
      Rails.logger.error "[SynkraProgramme] expiry failed for verification #{verification.id}: #{e.class}: #{e.message}"
    end
  end

  def lapse_account(verification)
    subscription = SynkraSubscription.find_by(account_id: verification.account_id)
    return if subscription.nil? || subscription.pricing_programme != verification.programme

    pricing = Billing::ProgrammePricingService.new(subscription)
    if SynkraProgrammeVerification.best_active_programme(subscription.account_id)
      pricing.apply!
    else
      pricing.lapse_to_free!
      Billing::ProgrammeMailer.programme_expired(verification: verification).deliver_later
    end
  end
end
