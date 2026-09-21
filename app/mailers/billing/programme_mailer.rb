# Synkra discount programmes: emails sent to applicants and to the
# Synkra team (as opposed to Billing::NotificationMailer, which emails
# an account's admins about their own subscription usage).
class Billing::ProgrammeMailer < ApplicationMailer
  PROGRAMME_NAMES = { 'student' => 'Student', 'community' => 'Community Access' }.freeze

  # Goes to the student's institutional address, not the account email.
  def student_code(verification:, code:)
    return unless smtp_config_set_or_development?

    @code = code
    @ttl_minutes = (SynkraProgrammeVerification::OTP_TTL / 60).to_i

    send_mail_with_liquid(
      to: verification.institution_email,
      subject: I18n.t('billing_mailer.student_code.subject')
    )
  end

  def expiry_warning(verification:, days_left:)
    return unless smtp_config_set_or_development?

    @programme_name = PROGRAMME_NAMES[verification.programme]
    @days_left = days_left
    @expires_on = verification.expires_at.in_time_zone(SynkraProgrammeVerification::ELIGIBILITY_TIME_ZONE).strftime('%-d %B %Y')
    recipients = admin_emails(verification.account)
    return if recipients.empty?

    send_mail_with_liquid(
      to: recipients,
      subject: I18n.t('billing_mailer.programme_expiry_warning.subject', programme: @programme_name, days: days_left)
    )
  end

  def programme_expired(verification:)
    return unless smtp_config_set_or_development?

    @programme_name = PROGRAMME_NAMES[verification.programme]
    recipients = admin_emails(verification.account)
    return if recipients.empty?

    send_mail_with_liquid(
      to: recipients,
      subject: I18n.t('billing_mailer.programme_expired.subject', programme: @programme_name)
    )
  end

  # outcome: 'approved' | 'needs_info' | 'rejected'
  def review_outcome(verification:, outcome:)
    return unless smtp_config_set_or_development?

    @programme_name = PROGRAMME_NAMES[verification.programme]
    @outcome = outcome
    @note = verification.review_note.to_s
    recipients = admin_emails(verification.account)
    return if recipients.empty?

    send_mail_with_liquid(
      to: recipients,
      subject: I18n.t("billing_mailer.programme_review_outcome.subject_#{outcome}", programme: @programme_name)
    )
  end

  # Goes to the Synkra team (PROGRAMME_REVIEW_EMAIL), not the applicant.
  def review_requested(verification:)
    return unless smtp_config_set_or_development?

    recipient = ENV.fetch('PROGRAMME_REVIEW_EMAIL', nil)
    return if recipient.blank?

    @programme_name = PROGRAMME_NAMES[verification.programme]
    @account_name = verification.account.name
    @review_url = "#{ENV.fetch('FRONTEND_URL', '')}/super_admin/programme_reviews/#{verification.id}"

    send_mail_with_liquid(
      to: recipient,
      subject: I18n.t('billing_mailer.programme_review_requested.subject', programme: @programme_name, account: @account_name)
    )
  end

  private

  def admin_emails(account)
    account.administrators.pluck(:email).compact
  end

  def liquid_locals
    super.merge(
      {
        code: @code, ttl_minutes: @ttl_minutes, programme_name: @programme_name, days_left: @days_left,
        expires_on: @expires_on, outcome: @outcome, note: @note, account_name: @account_name, review_url: @review_url
      }
    )
  end
end
