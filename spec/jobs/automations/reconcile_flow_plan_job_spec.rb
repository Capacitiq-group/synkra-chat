require 'rails_helper'

RSpec.describe Automations::ReconcileFlowPlanJob do
  describe '#perform' do
    it 're-enqueues a sync for a subscription whose sync never landed' do
      account = create(:account)
      subscription = account.synkra_subscription
      subscription.update!(
        flow_provisioned_at: 1.day.ago,
        plan: 'starter',
        plan_changed_at: 1.hour.ago,
        flow_plan_synced_at: nil
      )

      expect { described_class.perform_now }
        .to have_enqueued_job(Automations::SyncFlowPlanJob).with(account.id, 'starter')
    end

    it 'does not touch a subscription that is already in sync' do
      account = create(:account)
      subscription = account.synkra_subscription
      subscription.update!(
        flow_provisioned_at: 1.day.ago,
        plan: 'starter',
        plan_changed_at: 1.hour.ago,
        flow_plan_synced_at: 30.minutes.ago
      )

      expect { described_class.perform_now }
        .not_to have_enqueued_job(Automations::SyncFlowPlanJob)
    end

    it 'skips accounts that have no shadow client yet' do
      create(:account) # flow_provisioned_at nil by default

      expect { described_class.perform_now }
        .not_to have_enqueued_job(Automations::SyncFlowPlanJob)
    end
  end
end
