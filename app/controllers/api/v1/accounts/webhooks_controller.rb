class Api::V1::Accounts::WebhooksController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :ensure_api_and_webhooks_enabled
  before_action :fetch_webhook, only: [:update, :destroy]

  def index
    @webhooks = Current.account.webhooks
  end

  def create
    @webhook = Current.account.webhooks.new(webhook_params)
    @webhook.save!
  end

  def update
    @webhook.update!(webhook_params)
  end

  def destroy
    @webhook.destroy!
    head :ok
  end

  private

  # Synkra Chat: webhooks are a paid-tier feature. Free accounts see a
  # 402 with a clear message instead of a 500 or a silent no-op.
  def ensure_api_and_webhooks_enabled
    return if Current.account.feature_enabled?(:api_and_webhooks)

    render json: { error: I18n.t('errors.api_and_webhooks_paid_only') },
           status: :payment_required
  end

  def webhook_params
    params.require(:webhook).permit(:inbox_id, :name, :url, subscriptions: [])
  end

  def fetch_webhook
    @webhook = Current.account.webhooks.find(params[:id])
  end
end
