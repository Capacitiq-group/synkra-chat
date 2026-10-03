# Synkra Chat global identity layer: emails for the global-identity OTP
# flow, distinct from ContactIdentityMailer (which operates on a
# business-specific Contact, not the cross-business SynkraGlobalUser).
class SynkraIdentityMailer < ApplicationMailer
  def otp_code(global_user:, code:)
    return unless smtp_config_set_or_development?
    return if global_user.email.blank?

    @global_user = global_user
    @code = code

    send_mail_with_liquid(
      to: global_user.email,
      subject: I18n.t('synkra_identity_mailer.otp_code.subject')
    )
  end

  private

  def liquid_locals
    super.merge({ global_user: @global_user, code: @code })
  end
end
