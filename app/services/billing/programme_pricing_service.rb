# Discount programmes: keeps an account's Paystack subscription priced
# under the programme it currently qualifies for.
#
# - apply! : the account just became eligible (or eligible for a better
#   programme) while ALREADY paying the standard price - move its Paystack
#   subscription onto the programme plan from the next billing date.
#   Accounts that are not paying yet just get the programme price at
#   their next checkout (see SubscriptionsController#checkout).
# - lapse_to_free! : eligibility ended and nothing else covers the
#   account - move it to Free. It is never silently charged the
#   standard price ("no verified status = no programme billing").
class Billing::ProgrammePricingService
  def initialize(account_or_subscription)
    @subscription =
      account_or_subscription.is_a?(SynkraSubscription) ? account_or_subscription : account_or_subscription.synkra_subscription
    @paystack = Billing::PaystackService.new
  end

  def apply!
    return false if @subscription.nil? || @subscription.plan == 'free'
    return false if @subscription.paystack_subscription_code.blank?

    programme = SynkraProgrammeVerification.best_active_programme(@subscription.account_id)
    return false if programme.nil? || programme == @subscription.pricing_programme

    switch_paystack_plan!(programme)
  rescue StandardError => e
    # Never let a pricing sync failure undo a verification that succeeded.
    Rails.logger.error "[SynkraProgramme] apply! failed for subscription #{@subscription&.id}: #{e.class}: #{e.message}"
    false
  end

  def lapse_to_free!
    return if @subscription.nil?

    if @subscription.paystack_subscription_code.present?
      result = @paystack.cancel_subscription(
        subscription_code: @subscription.paystack_subscription_code,
        email_token: @subscription.paystack_email_token
      )
      unless result.success?
        Rails.logger.error "[SynkraProgramme] Couldn't cancel Paystack subscription for lapsed programme (subscription #{@subscription.id}): #{result.error}"
      end
    end

    @subscription.update!(pending_plan: 'free')
    @subscription.apply_pending_plan_change!
    @subscription.update!(
      pricing_programme: nil,
      paystack_subscription_code: nil,
      paystack_email_token: nil,
      cancel_at_period_end: false,
      status: 'active'
    )
  end

  private

  # Order matters: create the new (future-dated) subscription first, then
  # cancel the old one. If cancelling fails the new one is rolled back,
  # so the customer is never left with two live subscriptions (double
  # charge) or - worse for us - none.
  def switch_paystack_plan!(programme)
    new_code = SynkraPlan.for_programme(@subscription.plan, programme)[:paystack_plan_code]
    if new_code.blank? || @subscription.paystack_authorization_code.blank? || @subscription.paystack_customer_code.blank?
      Rails.logger.error "[SynkraProgramme] Can't move subscription #{@subscription.id} to #{programme} pricing: missing plan code or stored authorization"
      return false
    end

    created = @paystack.create_subscription(
      customer_code: @subscription.paystack_customer_code,
      plan_code: new_code,
      authorization_code: @subscription.paystack_authorization_code,
      start_date: @subscription.current_period_end || 1.month.from_now
    )
    unless created.success?
      Rails.logger.error "[SynkraProgramme] Couldn't create #{programme} Paystack subscription (subscription #{@subscription.id}): #{created.error}"
      return false
    end

    cancelled = @paystack.cancel_subscription(
      subscription_code: @subscription.paystack_subscription_code,
      email_token: @subscription.paystack_email_token
    )
    unless cancelled.success?
      @paystack.cancel_subscription(
        subscription_code: created.data['subscription_code'],
        email_token: created.data['email_token']
      )
      Rails.logger.error "[SynkraProgramme] Couldn't cancel old Paystack subscription for subscription #{@subscription.id}; rolled back the new one"
      return false
    end

    @subscription.update!(
      pricing_programme: programme,
      paystack_subscription_code: created.data['subscription_code'],
      paystack_email_token: created.data['email_token']
    )
    true
  end
end
