class Automations::SyncFlowPlanJob < ApplicationJob
  queue_as :default

  class SyncError < StandardError; end

  retry_on SyncError, Faraday::ConnectionFailed, Faraday::TimeoutError,
           wait: :polynomially_longer, attempts: 5

  def perform(account_id, chat_plan)
    account = Account.find_by(id: account_id)
    return unless account

    subscription = account.synkra_subscription
    return unless subscription

    result = Automations::FlowClient.new.update_plan!(
      chat_account_id: account.id,
      chat_plan: chat_plan
    )

    return if result.success?

    Rails.logger.error("Automations::SyncFlowPlanJob failed for account #{account.id} (plan=#{chat_plan}): #{result.error}")
    raise SyncError, result.error.to_s
  end
end
