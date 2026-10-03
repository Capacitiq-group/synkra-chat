class CreateSynkraBilling < ActiveRecord::Migration[7.2]
  def change
    # One subscription per Chat account (business). Synkra's own billing,
    # deliberately NOT Chatwoot's built-in billing concepts - separate
    # from Flow's billing entirely (no cross-subsidy between products).
    create_table :synkra_subscriptions do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :plan, null: false, default: 'basic' # 'basic' | 'pro'
      t.string :status, null: false, default: 'active' # 'active' | 'past_due' | 'restricted' | 'cancelled'
      t.string :billing_cycle, null: false, default: 'monthly'
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.boolean :cancel_at_period_end, null: false, default: false
      t.datetime :past_due_since
      t.string :paystack_customer_code
      t.string :paystack_subscription_code
      t.string :paystack_email_token
      t.string :pending_plan # set when a downgrade is scheduled for period end
      t.decimal :last_usage_warning_threshold # tracks which of 0.7/0.9/1.0 we've already notified about this period, so warnings never repeat
      t.timestamps
    end

    # Central usage ledger. Every billable event is recorded here at the
    # moment it happens - billing/limit-enforcement reads from this,
    # never recomputes usage by scanning other tables after the fact.
    create_table :synkra_usage_events do |t|
      t.references :account, null: false, foreign_key: true
      t.string :resource_type, null: false # 'business_initiated_message' | 'storage_mb' | 'ai_request' | 'voice_minute' (only the first is actually metered in V1)
      t.decimal :quantity, null: false, default: 1
      t.datetime :occurred_at, null: false
      t.string :source # e.g. 'agent_reply', 'campaign', 'automation', 'flow'
      t.bigint :reference_id # optional pointer back to the actual Message/etc, not a real FK (polymorphic-lite, kept loose on purpose)
      t.string :reference_type
      t.timestamps
    end
    add_index :synkra_usage_events, [:account_id, :resource_type, :occurred_at], name: 'index_usage_events_on_account_resource_time'
  end
end
