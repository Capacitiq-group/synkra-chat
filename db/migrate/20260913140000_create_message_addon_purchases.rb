class CreateMessageAddonPurchases < ActiveRecord::Migration[7.2]
  # Message add-ons (confirmed by Refilwe 13 Sep 2026, same rate/pack
  # structure as Flow's own email add-ons: R0.01/message, non-expiring,
  # FIFO in spirit though a single running balance is equivalent here
  # since nothing expires - see Billing::MessageAddonPack).
  #
  # purchased_message_credits is the live spendable balance -
  # incremented by a completed purchase, decremented one at a time as
  # SynkraSubscription#consume_purchased_message_credit_if_over_plan_allowance!
  # is called (only once the plan's own period allowance is exhausted -
  # see Message#record_synkra_usage_event). message_addon_purchases is
  # the audit trail of how that balance got there - never mutated after
  # completion, so support/billing disputes have a real paper trail.
  def change
    add_column :synkra_subscriptions, :purchased_message_credits, :integer, default: 0, null: false

    create_table :message_addon_purchases do |t|
      t.references :account, null: false, foreign_key: true
      t.string :pack_key, null: false
      t.integer :units, null: false
      t.integer :price_zar, null: false
      t.string :paystack_reference, null: false
      t.string :status, null: false, default: 'pending' # pending -> completed
      t.timestamps
    end
    add_index :message_addon_purchases, :paystack_reference, unique: true
  end
end
