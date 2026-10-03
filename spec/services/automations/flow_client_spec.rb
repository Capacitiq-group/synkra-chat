require 'rails_helper'

RSpec.describe Automations::FlowClient do
  let(:base_url) { 'https://api.synkra.co.za' }
  let(:shared_secret) { 'test-shared-secret' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('CHAT_SHARED_SECRET', nil).and_return(shared_secret)
  end

  describe '#provision!' do
    let(:client) { described_class.new }

    context 'when successful' do
      before do
        stub_request(:post, "#{base_url}/internal/chat-accounts/provision")
          .with(
            body: { chat_account_id: '42', chat_plan: 'free' }.to_json,
            headers: { 'X-Synkra-Secret' => shared_secret }
          )
          .to_return(
            status: 200,
            body: { api_key: 'SYN_abc123', key_id: 'key1' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns a successful result with the api key' do
        result = client.provision!(chat_account_id: 42, chat_plan: 'free')
        expect(result.success?).to be true
        expect(result.data['api_key']).to eq('SYN_abc123')
      end
    end

    context 'when Flow rejects the request' do
      before do
        stub_request(:post, "#{base_url}/internal/chat-accounts/provision")
          .to_return(status: 401, body: { detail: 'Unauthorized' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns a failed result with the error detail' do
        result = client.provision!(chat_account_id: 42, chat_plan: 'free')
        expect(result.success?).to be false
        expect(result.error).to eq('Unauthorized')
      end
    end

    context 'when CHAT_SHARED_SECRET is not configured' do
      let(:shared_secret) { nil }

      it 'fails fast without making a request' do
        result = client.provision!(chat_account_id: 42, chat_plan: 'free')
        expect(result.success?).to be false
        expect(result.error).to match(/not configured/)
        expect(WebMock).not_to have_requested(:post, "#{base_url}/internal/chat-accounts/provision")
      end
    end

    context 'when the connection itself fails' do
      before do
        stub_request(:post, "#{base_url}/internal/chat-accounts/provision")
          .to_raise(Faraday::ConnectionFailed.new('connection refused'))
      end

      it 'returns a failed result rather than raising' do
        result = client.provision!(chat_account_id: 42, chat_plan: 'free')
        expect(result.success?).to be false
        expect(result.error).to match(/connection refused/)
      end
    end
  end

  describe '#credits' do
    context 'without a subscription (no key)' do
      it 'fails without making a request' do
        result = described_class.new.credits
        expect(result.success?).to be false
        expect(result.error).to match(/No Automations API key/)
      end
    end

    context 'with a keyed subscription' do
      let(:account) { create(:account) }
      let(:subscription) { account.synkra_subscription }
      let(:client) { described_class.new(subscription) }

      before { subscription.update!(flow_api_key: 'SYN_realkey') }

      it 'authenticates with the account bearer token' do
        stub_request(:get, "#{base_url}/api/v1/credits")
          .with(headers: { 'Authorization' => 'Bearer SYN_realkey' })
          .to_return(
            status: 200,
            body: { tier: 'free', ai_ops: { included: 0, used: 0 }, emails: { included: 300, used: 10 } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = client.credits
        expect(result.success?).to be true
        expect(result.data['tier']).to eq('free')
      end
    end
  end
end
