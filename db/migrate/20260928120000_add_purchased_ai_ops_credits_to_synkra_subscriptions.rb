class AddPurchasedAiOpsCreditsToSynkraSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :synkra_subscriptions, :purchased_ai_ops_credits,
               :integer, default: 0, null: false
  end
end
