require 'rails_helper'

RSpec.describe SynkraSubscription do
  let(:account) { create(:account) }
  let(:subscription) { account.synkra_subscription }

  describe '#change_plan!' do
    it 'applies an upgrade immediately and enqueues a Flow sync' do
      expect { subscription.change_plan!('pro') }
        .to have_enqueued_job(Automations::SyncFlowPlanJob).with(account.id, 'pro')
      expect(subscription.reload.plan).to eq('pro')
      expect(subscription.pending_plan).to be_nil
      expect(subscription.plan_changed_at).to be_present
    end

    it 'schedules a downgrade for period end instead of applying it immediately' do
      subscription.update!(plan: 'pro', plan_changed_at: Time.current)

      expect { subscription.change_plan!('starter') }
        .not_to have_enqueued_job(Automations::SyncFlowPlanJob)
      expect(subscription.reload.plan).to eq('pro')
      expect(subscription.pending_plan).to eq('starter')
    end

    it 'ignores an invalid plan' do
      expect { subscription.change_plan!('not-a-real-plan') }
        .not_to(change { subscription.reload.plan })
    end
  end

  describe '#apply_pending_plan_change!' do
    it 'applies the pending downgrade and syncs Flow' do
      subscription.update!(plan: 'pro', pending_plan: 'starter')

      expect { subscription.apply_pending_plan_change! }
        .to have_enqueued_job(Automations::SyncFlowPlanJob).with(account.id, 'starter')
      expect(subscription.reload.plan).to eq('starter')
      expect(subscription.pending_plan).to be_nil
    end

    it 'does nothing when there is no pending plan' do
      expect { subscription.apply_pending_plan_change! }
        .not_to have_enqueued_job(Automations::SyncFlowPlanJob)
    end
  end

  describe '#plan_sync_stale?' do
    it 'is false when there is no shadow client yet' do
      subscription.update!(flow_provisioned_at: nil, plan_changed_at: 1.hour.ago, flow_plan_synced_at: nil)
      expect(subscription).not_to be_plan_sync_stale
    end

    it 'is false when the plan has never actually changed since provisioning' do
      subscription.update!(flow_provisioned_at: 1.hour.ago, plan_changed_at: nil)
      expect(subscription).not_to be_plan_sync_stale
    end

    it 'is true when a plan change has never been synced' do
      subscription.update!(flow_provisioned_at: 1.hour.ago, plan_changed_at: 30.minutes.ago, flow_plan_synced_at: nil)
      expect(subscription).to be_plan_sync_stale
    end

    it 'is true when the last sync predates the last plan change' do
      subscription.update!(
        flow_provisioned_at: 1.hour.ago,
        flow_plan_synced_at: 40.minutes.ago,
        plan_changed_at: 10.minutes.ago
      )
      expect(subscription).to be_plan_sync_stale
    end

    it 'is false when the last sync is at or after the last plan change' do
      subscription.update!(
        flow_provisioned_at: 1.hour.ago,
        plan_changed_at: 40.minutes.ago,
        flow_plan_synced_at: 10.minutes.ago
      )
      expect(subscription).not_to be_plan_sync_stale
    end
  end

  describe '#automations_credits' do
    it 'delegates to Automations::FlowClient scoped to this subscription' do
      flow_client = instance_double(Automations::FlowClient)
      expect(Automations::FlowClient).to receive(:new).with(subscription).and_return(flow_client)
      expect(flow_client).to receive(:credits)

      subscription.automations_credits
    end
  end
end
