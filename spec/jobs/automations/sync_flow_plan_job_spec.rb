require 'rails_helper'

RSpec.describe Automations::SyncFlowPlanJob do
  let(:account) { create(:account) }
  let(:subscription) { account.synkra_subscription }
  let(:flow_client) { instance_double(Automations::FlowClient) }

  before do
    subscription.update!(plan: 'starter', plan_changed_at: Time.current)
    allow(Automations::FlowClient).to receive(:new).and_return(flow_client)
  end

  describe '#perform' do
    context 'when the sync succeeds and the plan has not changed again since' do
      it 'stamps flow_plan_synced_at' do
        allow(flow_client).to receive(:update_plan!)
          .with(chat_account_id: account.id, chat_plan: 'starter')
          .and_return(Automations::FlowClient::Result.new(success?: true, data: {}))

        expect { described_class.perform_now(account.id, 'starter') }
          .to change { subscription.reload.flow_plan_synced_at }.from(nil)
      end
    end

    context 'when the plan changed again while this job was in flight' do
      it 'does not stamp flow_plan_synced_at - a newer sync job owns that' do
        allow(flow_client).to receive(:update_plan!) do
          # Simulate a second, later plan change landing mid-job.
          subscription.update!(plan: 'business', plan_changed_at: Time.current)
          Automations::FlowClient::Result.new(success?: true, data: {})
        end

        described_class.perform_now(account.id, 'starter')
        expect(subscription.reload.flow_plan_synced_at).to be_nil
      end
    end

    context 'when Flow rejects the update' do
      it 'raises SyncError to trigger retry_on and does not stamp' do
        allow(flow_client).to receive(:update_plan!)
          .and_return(Automations::FlowClient::Result.new(success?: false, error: 'boom'))

        expect { described_class.perform_now(account.id, 'starter') }
          .to raise_error(described_class::SyncError, 'boom')
        expect(subscription.reload.flow_plan_synced_at).to be_nil
      end
    end
  end
end
