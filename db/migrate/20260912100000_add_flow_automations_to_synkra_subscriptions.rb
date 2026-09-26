class AddFlowAutomationsToSynkraSubscriptions < ActiveRecord::Migration[7.2]
  # Chat<->Flow bridge (12 Sep 2026): a SYN_... API key Chat's backend uses
  # to call Flow's scoped v1 API (credits + chat-relevant workflow triggers)
  # on behalf of this account's auto-provisioned Flow shadow user. Never
  # shown to the business - stored encrypted, read only by
  # Automations::FlowClient. See app/services/automations/flow_client.rb.
  def change
    add_column :synkra_subscriptions, :flow_api_key, :string
    add_column :synkra_subscriptions, :flow_provisioned_at, :datetime
  end
end
