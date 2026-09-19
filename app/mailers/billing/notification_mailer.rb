# Synkra Chat billing: notifications sent to the account's admins (not
# customers) about their own subscription/usage - distinct from
# ContactIdentityMailer/SynkraIdentityMailer, which email end customers.
class Billing::NotificationMailer < ApplicationMailer
  def usage_warning(subscription:, threshold:)
    return unless smtp_config_set_or_development?

    @subscription = subscription
    @threshold_percent = (threshold * 100).to_i
    @plan_name = subscription.plan_config[:name]
    @recipients = admin_emails(subscription.account)
    return if @recipients.empty?

    send_mail_with_liquid(
      to: @recipients,
      subject: I18n.t('billing_mailer.usage_warning.subject', percent: @threshold_percent)
    )
  end

  # Deliberately separate from usage_warning above rather than a
  # shared "resource type" param - storage warnings can reach 100%
  # (meaning uploads are now BLOCKED, not just close to a limit the
  # way messages/AI-ops are), which needs different, more urgent
  # copy at that threshold. See
  # SynkraSubscription#next_unnotified_storage_threshold for why this
  # is tracked on its own column too, not reusing the message one.
  def storage_warning(subscription:, threshold:)
    return unless smtp_config_set_or_development?

    @subscription = subscription
    @threshold_percent = (threshold * 100).to_i
    @plan_name = subscription.plan_config[:name]
    @blocked = threshold >= 1.0
    @recipients = admin_emails(subscription.account)
    return if @recipients.empty?

    send_mail_with_liquid(
      to: @recipients,
      subject: I18n.t(
        @blocked ? 'billing_mailer.storage_warning.subject_blocked' : 'billing_mailer.storage_warning.subject',
        percent: @threshold_percent
      )
    )
  end

  def payment_failed(subscription:)
    return unless smtp_config_set_or_development?

    @subscription = subscription
    @plan_name = subscription.plan_config[:name]
    @recipients = admin_emails(subscription.account)
    return if @recipients.empty?

    send_mail_with_liquid(
      to: @recipients,
      subject: I18n.t('billing_mailer.payment_failed.subject')
    )
  end

  def account_restricted(subscription:)
    return unless smtp_config_set_or_development?

    @subscription = subscription
    @plan_name = subscription.plan_config[:name]
    @recipients = admin_emails(subscription.account)
    return if @recipients.empty?

    send_mail_with_liquid(
      to: @recipients,
      subject: I18n.t('billing_mailer.account_restricted.subject')
    )
  end

  private

  def admin_emails(account)
    account.administrators.pluck(:email).compact
  end

  def liquid_locals
    super.merge({ subscription: @subscription, threshold_percent: @threshold_percent, plan_name: @plan_name })
  end
end
