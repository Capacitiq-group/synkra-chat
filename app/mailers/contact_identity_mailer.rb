# Synkra Chat identity layer: emails sent directly to widget customers
# (not staff/agents) as part of confirming their email address and
# letting them continue a conversation from a different device.
class ContactIdentityMailer < ApplicationMailer
  def verify_email(contact:, verification_url:)
    return unless smtp_config_set_or_development?
    return if contact.email.blank?

    @contact = contact
    @verification_url = verification_url

    send_mail_with_liquid(
      to: contact.email,
      subject: I18n.t('contact_identity_mailer.verify_email.subject')
    )
  end

  def continue_conversation(contact:, continuation_url:)
    return unless smtp_config_set_or_development?
    return if contact.email.blank?

    @contact = contact
    @continuation_url = continuation_url

    send_mail_with_liquid(
      to: contact.email,
      subject: I18n.t('contact_identity_mailer.continue_conversation.subject')
    )
  end

  private

  def liquid_locals
    super.merge({ contact: @contact })
  end
end
