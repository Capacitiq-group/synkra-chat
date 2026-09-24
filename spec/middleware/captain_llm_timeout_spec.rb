require 'rails_helper'

RSpec.describe CaptainLlmTimeout do
  let(:app) { ->(_env) { [200, {}, ['ok']] } }
  subject(:middleware) { described_class.new(app) }

  it 'sets rack-timeout.service_timeout for captain task paths' do
    env = { 'PATH_INFO' => '/api/v1/accounts/3/captain/tasks/reply_suggestion' }
    middleware.call(env)
    expect(env['rack-timeout.service_timeout']).to eq(60)
  end

  it 'does not touch other account paths' do
    env = { 'PATH_INFO' => '/api/v1/accounts/3/conversations' }
    middleware.call(env)
    expect(env).not_to have_key('rack-timeout.service_timeout')
  end
end
