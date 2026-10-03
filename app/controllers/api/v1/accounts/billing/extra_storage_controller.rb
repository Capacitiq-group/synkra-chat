# Extra storage beyond a plan's storage_mb_allowance - R30/GB/month
# (SynkraPlan::EXTRA_STORAGE_PRICE_ZAR_PER_GB, confirmed by Refilwe).
#
# Same model as extra seats (see ExtraSeatsController's comment):
# grants GB immediately with NO CHARGE at purchase time, first and all
# subsequent charges happen automatically at each plan renewal via
# Billing::PaystackWebhookHandler#bill_extra_storage_for_renewal - not
# through this controller. This recurring mechanism has NOT been
# tested against a real Paystack account - verify end-to-end before
# relying on it for real customer billing.
class Api::V1::Accounts::Billing::ExtraStorageController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(SynkraSubscription) }
  before_action :fetch_subscription

  def create
    gb = params[:gb].to_i
    if gb <= 0
      render json: { error: 'GB must be positive' }, status: :unprocessable_entity
      return
    end

    result = @subscription.purchase_extra_storage!(gb)
    if result.success?
      render json: { purchased_extra_storage_gb: @subscription.reload.purchased_extra_storage_gb,
                      effective_storage_mb_allowance: @subscription.effective_storage_mb_allowance }
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  private

  def fetch_subscription
    @subscription = Current.account.synkra_subscription
  end
end
