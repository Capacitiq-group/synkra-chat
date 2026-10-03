# Automations (Chat<->Flow bridge) key management for support/incident
# response. There is deliberately no customer-facing equivalent - a
# business never manages its own Automations key (see
# app/services/automations/flow_client.rb and
# docs/synkra/automations-flow-bridge.md for why).
namespace :automations do
  desc 'List all Automations API keys for an account: rake automations:list_keys[account_id]'
  task :list_keys, [:account_id] => :environment do |_t, args|
    account = Account.find(args[:account_id])
    result = Automations::FlowClient.new.list_keys(chat_account_id: account.id)

    if result.success?
      (result.data['keys'] || []).each do |key|
        status = key['revoked_at'].present? ? "revoked at #{key['revoked_at']}" : 'active'
        puts "#{key['id']}  #{key['key_prefix']}...  #{status}  last used: #{key['last_used_at'] || 'never'}"
      end
    else
      puts "Failed: #{result.error}"
    end
  end

  desc 'Mint an additional Automations key for an account: rake automations:add_key[account_id]'
  task :add_key, [:account_id] => :environment do |_t, args|
    account = Account.find(args[:account_id])
    result = Automations::FlowClient.new.add_key!(chat_account_id: account.id)

    if result.success?
      puts "New key minted: #{result.data['api_key']}"
      puts 'This is shown once and not stored anywhere by this task - if it needs to replace the ' \
           "account's primary key, update SynkraSubscription#flow_api_key by hand and revoke the old key_id."
    else
      puts "Failed: #{result.error}"
    end
  end

  desc 'Revoke an Automations key by id: rake automations:revoke_key[account_id,key_id]'
  task :revoke_key, %i[account_id key_id] => :environment do |_t, args|
    account = Account.find(args[:account_id])
    result = Automations::FlowClient.new.revoke_key!(chat_account_id: account.id, key_id: args[:key_id])

    if result.success?
      puts "Revoked #{args[:key_id]} for account #{account.id}."
      subscription = account.synkra_subscription
      if subscription&.flow_api_key.present?
        puts 'NOTE: this account still has flow_api_key stored locally - if the revoked key IS ' \
             'that stored key, Automations will start failing for this business until a new key ' \
             'is minted (automations:add_key) and saved onto SynkraSubscription#flow_api_key by hand.'
      end
    else
      puts "Failed: #{result.error}"
    end
  end
end
