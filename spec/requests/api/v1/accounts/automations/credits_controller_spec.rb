require 'rails_helper'

RSpec.describe 'Automations Credits API', type: :request do
  let(:account) { create(:account) }
  let(:subscription) { account.synkra_subscription }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/<account_id>/automations/credits' do
    context 'when it is an authenticated agent' do
      it 'returns unauthorized - billing/automations is admin-only' do
        get "/api/v1/accounts/#{account.id}/automations/credits",
            headers: agent.create_new_auth_token,
            as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the shadow client has not finished provisioning yet' do
      it 'returns a provisioning status without calling Flow' do
        expect(Automations::FlowClient).not_to receive(:new)

        get "/api/v1/accounts/#{account.id}/automations/credits",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['status']).to eq('provisioning')
      end
    end

    context 'when provisioned and Flow responds successfully' do
      before { subscription.update!(flow_api_key: 'SYN_realkey') }

      it 'returns the usage summary, never the api key' do
        flow_client = instance_double(Automations::FlowClient)
        allow(Automations::FlowClient).to receive(:new).with(subscription).and_return(flow_client)
        allow(flow_client).to receive(:credits).and_return(
          Automations::FlowClient::Result.new(
            success?: true,
            data: { 'tier' => 'starter', 'ai_ops' => { 'included' => 1250, 'used' => 10 },
                     'emails' => { 'included' => 3000, 'used' => 50 } }
          )
        )

        get "/api/v1/accounts/#{account.id}/automations/credits",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['status']).to eq('ready')
        expect(body['tier']).to eq('starter')
        expect(body['ai_ops']['included']).to eq(1250)
        expect(body).not_to have_key('flow_api_key')
        expect(response.body).not_to include('SYN_realkey')
      end
    end

    context 'when provisioned but Flow is unreachable' do
      before { subscription.update!(flow_api_key: 'SYN_realkey') }

      it 'returns a service_unavailable error status' do
        flow_client = instance_double(Automations::FlowClient)
        allow(Automations::FlowClient).to receive(:new).with(subscription).and_return(flow_client)
        allow(flow_client).to receive(:credits).and_return(
          Automations::FlowClient::Result.new(success?: false, error: 'connection refused')
        )

        get "/api/v1/accounts/#{account.id}/automations/credits",
            headers: administrator.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body['status']).to eq('error')
      end
    end
  end
end
