# Synkra discount programmes: emails sent to the applicant (as opposed
# to Billing::NotificationMailer, which emails an account's admins
# about their own subscription).
class Billing::ProgrammeMailer < ApplicationMailer
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

  private

  def liquid_locals
    super.merge({ code: @code, ttl_minutes: @ttl_minutes })
  end
end
