# Self-heals an Automations::ProvisionFlowJob that exhausted its retries
# (or never ran - e.g. the process died before an enqueued job executed).
# 2 hours is comfortably longer than ProvisionFlowJob's own 5-attempt
# polynomially_longer backoff window, so this never fires while a normal
# retry is still in flight - only once that job has genuinely given up.
class Automations::RetryStuckProvisioningJob < ApplicationJob
  queue_as :scheduled_jobs

  STUCK_AFTER = 2.hours

  def perform
    SynkraSubscription
      .where(flow_api_key: nil, flow_provisioned_at: nil)
      .where(created_at: ...STUCK_AFTER.ago)
      .find_each do |subscription|
        Rails.logger.info("Automations::RetryStuckProvisioningJob retrying account #{subscription.account_id}")
        Automations::ProvisionFlowJob.perform_later(subscription.account_id)
      end
  end
end
