class Automations::ProvisionFlowJob < ApplicationJob
  queue_as :default

  class ProvisioningError < StandardError; end

  # Retries on transient failure (network errors AND non-2xx responses,
  # both raised as ProvisioningError below) - provisioning isn't in the
  # account-creation request/response cycle (see the end of
  # Account#provision_synkra_subscription), so a slow/flaky Flow deploy
  # never blocks or fails account signup. Automations simply stays
  # unavailable (Automations::FlowClient#configured? / #keyed? calls
  # return a clear error) until this succeeds.
  retry_on ProvisioningError, Faraday::ConnectionFailed, Faraday::TimeoutError,
           wait: :polynomially_longer, attempts: 5

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account

    subscription = account.synkra_subscription
    return unless subscription
    return if subscription.flow_api_key.present? # already provisioned - idempotent

    result = Automations::FlowClient.new.provision!(
      chat_account_id: account.id,
      chat_plan: subscription.plan
    )

    unless result.success?
      Rails.logger.error("Automations::ProvisionFlowJob failed for account #{account.id}: #{result.error}")
      raise ProvisioningError, result.error.to_s
    end

    subscription.update!(
      flow_api_key: result.data['api_key'],
      flow_provisioned_at: Time.current
    )
  end
end
