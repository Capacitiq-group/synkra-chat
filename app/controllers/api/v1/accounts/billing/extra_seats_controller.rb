# Extra seats beyond a plan's staff_limit - R69/seat/month
# (SynkraPlan::EXTRA_SEAT_PRICE_ZAR, confirmed by Refilwe 13 Sep 2026).
#
# This controller grants seats immediately with NO CHARGE at purchase
# time - see SynkraSubscription#purchase_extra_seats!'s comment for
# why (decided over proration: simpler, can't double-charge, small
# accepted tradeoff of up to one free month per purchase). The actual
# first and all subsequent charges happen automatically at each plan
# renewal via
# Billing::PaystackWebhookHandler#bill_extra_seats_for_renewal - not
# through this controller, and there is no separate customer-facing
# action for it. This recurring mechanism has NOT been tested against
# a real Paystack account (no live credentials were available while
# building it) - verify it end-to-end (purchase seats, then
# simulate/wait for a renewal webhook, confirm exactly one charge for
# the right amount) before relying on it for real customer billing.
class Api::V1::Accounts::Billing::ExtraSeatsController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(SynkraSubscription) }
  before_action :fetch_subscription

  def create
    quantity = params[:quantity].to_i
    if quantity <= 0
      render json: { error: 'Quantity must be positive' }, status: :unprocessable_entity
      return
    end

    result = @subscription.purchase_extra_seats!(quantity)
    if result.success?
      render json: { purchased_extra_seats: @subscription.reload.purchased_extra_seats,
                      effective_seat_limit: @subscription.effective_seat_limit }
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  private

  def fetch_subscription
    @subscription = Current.account.synkra_subscription
  end
end
