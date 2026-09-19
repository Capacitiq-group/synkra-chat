# Informational only, by design: this never forces a password reset
# or any other action on the recipient - it's a heads-up so they can
# act themselves if they don't recognize the login. Reuses the
# existing UserSession (ip_address/city/country) infrastructure -
# no new schema needed for this.
class UserSecurityMailer < ApplicationMailer
  def new_login_notification(user:, session:)
    return unless smtp_config_set_or_development?
    return if user.email.blank?

    @user = user
    @session = session

    send_mail_with_liquid(
      to: user.email,
      subject: I18n.t('user_security_mailer.new_login_notification.subject')
    )
  end

  private

  def liquid_locals
    super.merge(
      user_name: @user.name,
      ip_address: @session.ip_address,
      location: [@session.city, @session.country].compact.join(', ').presence,
      sign_in_time: @session.last_activity_at&.strftime('%d %b %Y, %H:%M %Z')
    )
  end
end
