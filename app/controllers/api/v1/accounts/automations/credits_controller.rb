# "Automations" tab - the Chat-facing name for the Chat<->Flow bridge.
# Deliberately read-only: the business sees a usage summary, never the
# underlying flow_api_key (that's server-side only, in
# SynkraSubscription#flow_api_key) and never anything framed as "Flow"
# or "connect your account" (see Automations::FlowClient's header
# comment for why). Admin-only, matching billing's own authorization
# pattern.
class Api::V1::Accounts::Automations::CreditsController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(SynkraSubscription) }
  before_action :fetch_subscription

  def show
    if @subscription.flow_api_key.blank?
      # Provisioning is async (Automations::ProvisionFlowJob) - a
      # brand-new account can legitimately hit this for the first few
      # seconds. Not an error state; the frontend should treat this as
      # "still setting up" and can safely retry.
      render json: { status: 'provisioning' }
      return
    end

    result = @subscription.automations_credits
    if result.success?
      render json: { status: 'ready', **result.data.slice('tier', 'ai_ops', 'emails') }
    else
      render json: { status: 'error', error: result.error }, status: :service_unavailable
    end
  end

  private

  def fetch_subscription
    @subscription = Current.account.synkra_subscription
  end
end
