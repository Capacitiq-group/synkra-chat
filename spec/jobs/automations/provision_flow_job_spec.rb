require 'rails_helper'

RSpec.describe Automations::ProvisionFlowJob do
  let(:account) { create(:account) }
  let(:subscription) { account.synkra_subscription }

  describe '#perform' do
    context 'when the subscription is not yet provisioned' do
      before do
        allow(Automations::FlowClient).to receive(:new).and_return(flow_client)
      end

      let(:flow_client) { instance_double(Automations::FlowClient) }

      it 'stores the returned api key and provisioned timestamp' do
        allow(flow_client).to receive(:provision!)
          .with(chat_account_id: account.id, chat_plan: 'free')
          .and_return(Automations::FlowClient::Result.new(success?: true, data: { 'api_key' => 'SYN_new' }))

        expect { described_class.perform_now(account.id) }
          .to change { subscription.reload.flow_api_key }.from(nil).to('SYN_new')
        expect(subscription.reload.flow_provisioned_at).to be_present
      end

      it 'raises ProvisioningError (to trigger retry_on) when Flow rejects the request' do
        allow(flow_client).to receive(:provision!)
          .and_return(Automations::FlowClient::Result.new(success?: false, error: 'boom'))

        expect { described_class.perform_now(account.id) }
          .to raise_error(described_class::ProvisioningError, 'boom')
        expect(subscription.reload.flow_api_key).to be_nil
      end
    end

    context 'when the subscription is already provisioned' do
      before { subscription.update!(flow_api_key: 'SYN_existing', flow_provisioned_at: Time.current) }

      it 'is a no-op and never calls Flow' do
        expect(Automations::FlowClient).not_to receive(:new)
        described_class.perform_now(account.id)
        expect(subscription.reload.flow_api_key).to eq('SYN_existing')
      end
    end

    context 'when the account no longer exists' do
      it 'does nothing' do
        expect { described_class.perform_now(-1) }.not_to raise_error
      end
    end
  end
end
