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

    unless result.success?
      Rails.logger.error("Automations::SyncFlowPlanJob failed for account #{account.id} (plan=#{chat_plan}): #{result.error}")
      raise SyncError, result.error.to_s
    end

    # Only stamp if the subscription's plan is STILL what we just synced -
    # another change could have landed while this job was running/retrying,
    # in which case that later change (and its own sync job) is the one
    # that should get to claim "synced".
    subscription.update!(flow_plan_synced_at: Time.current) if subscription.reload.plan == chat_plan
  end
end
