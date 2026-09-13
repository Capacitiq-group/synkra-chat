# Extra seats beyond a plan's staff_limit - R69/seat/month
# (SynkraPlan::EXTRA_SEAT_PRICE_ZAR, confirmed by Refilwe 13 Sep 2026).
#
# IMPORTANT, READ BEFORE RELYING ON THIS IN PRODUCTION: this only
# builds the ONE-TIME charge for adding N seats right now (via
# Billing::PaystackService#charge_authorization against the card
# already on file from the account's last plan payment). It does NOT
# build automatic monthly re-billing of extra seats at each
# subscription renewal - unlike the base plan price (which rides
# Paystack's own recurring subscription billing), there is currently
# no mechanism that re-charges purchased_extra_seats * 69 every period.
# This needs a real decision (prorate first charge? bill extra seats
# as a separate recurring line item alongside
# Billing::PaystackWebhookHandler#handle_charge_success's existing
# renewal handling?) AND live testing against a real Paystack account
# before it can be trusted to touch a customer's card automatically -
# neither has happened yet. Right now, purchasing extra seats is a
# one-time charge that permanently raises the seat limit with no
# further billing - fine for manual/ops use, not yet fine as a
# self-serve recurring product feature.
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
