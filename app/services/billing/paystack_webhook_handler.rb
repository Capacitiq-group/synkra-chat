# Synkra Chat billing: processes verified Paystack webhook events and
# updates the local SynkraSubscription accordingly. Signature
# verification happens in the controller before this is ever called -
# this class trusts its input completely, so it must never be invoked
# directly from anywhere that hasn't already verified the signature.
class Billing::PaystackWebhookHandler
  def initialize(event)
    @event = event
    @data = event['data'] || {}
  end

  def process!
    case @event['event']
    when 'charge.success'
      handle_charge_success
    when 'subscription.create'
      handle_subscription_create
    when 'invoice.payment_failed'
      handle_payment_failed
    when 'subscription.disable', 'subscription.not_renew'
      handle_subscription_disabled
    else
      Rails.logger.info "[SynkraBilling] Unhandled Paystack event: #{@event['event']}"
    end
  end

  private

  def find_subscription
    account_id = @data.dig('metadata', 'synkra_account_id') || @data.dig('metadata', 'account_id')
    return nil if account_id.blank?

    SynkraSubscription.find_by(account_id: account_id)
  end

  def handle_charge_success
    subscription = find_subscription
    return if subscription.nil?

    # A successful charge always clears any past-due/restricted state,
    # whether it was the very first payment or a recovery payment.
    subscription.mark_active!
    subscription.start_new_period!
    subscription.apply_pending_plan_change!
  end

  def handle_subscription_create
    subscription = find_subscription
    return if subscription.nil?

    subscription.update!(
      paystack_subscription_code: @data['subscription_code'],
      paystack_email_token: @data['email_token'],
      paystack_customer_code: @data.dig('customer', 'customer_code')
    )
  end

  def handle_payment_failed
    subscription = find_subscription
    return if subscription.nil?

    was_already_past_due = subscription.past_due?
    subscription.mark_past_due!
    Billing::NotificationMailer.payment_failed(subscription: subscription).deliver_later unless was_already_past_due
    # Actually moving from past_due -> restricted happens on a
    # scheduled job (Billing::RestrictOverdueSubscriptionsJob) once the
    # grace period elapses, not immediately here - a single failed
    # charge should never instantly cut anyone off.
  end

  def handle_subscription_disabled
    subscription = find_subscription
    return if subscription.nil?

    subscription.update!(status: 'cancelled', paystack_subscription_code: nil)
  end
end
