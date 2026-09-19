# See Automations::UsageTracker for why this is fail-open and never
# allowed to affect the reply it's tracking usage for. Retries are
# short and few (unlike ProvisionFlowJob/SyncFlowPlanJob, which retry
# hard because losing a provisioning/plan-sync event is a real
# correctness problem) - losing one ai_ops tracking event on a rare
# double-failure is an acceptable, self-correcting-at-scale loss, not
# worth chasing indefinitely in the background.
class Automations::ConsumeCreditJob < ApplicationJob
  queue_as :low

  retry_on Faraday::ConnectionFailed, Faraday::TimeoutError, wait: 5.seconds, attempts: 2

  def perform(account_id, kind, amount)
    account = Account.find_by(id: account_id)
    return unless account

    subscription = account.synkra_subscription
    return unless subscription&.flow_api_key.present?

    result = Automations::FlowClient.new(subscription).consume_credit!(kind: kind, amount: amount)
    return if result.success?

    # Deliberately just a log line, not an exception - see the class
    # comment. A 402 (out of credit) is an expected, common outcome
    # here, not a bug to retry or alert on.
    Rails.logger.info("Automations::ConsumeCreditJob: account #{account.id} kind=#{kind} amount=#{amount} not recorded: #{result.error}")
  end
end
