# Self-heals a SynkraSubscription#sync_flow_plan! that never landed on
# Flow - Automations::SyncFlowPlanJob exhausted its retries, or was
# enqueued but the process died before running it. Runs hourly,
# matching Billing::RestrictOverdueSubscriptionsJob's cadence (see
# config/schedule.yml) - there is no urgency here that justifies
# checking more often than that.
class Automations::ReconcileFlowPlanJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    SynkraSubscription.where.not(flow_provisioned_at: nil).find_each do |subscription|
      next unless subscription.plan_sync_stale?

      Rails.logger.info("Automations::ReconcileFlowPlanJob re-syncing account #{subscription.account_id} (plan=#{subscription.plan})")
      Automations::SyncFlowPlanJob.perform_later(subscription.account_id, subscription.plan)
    end
  end
end
