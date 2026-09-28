class CreateAiOpsAddonPurchases < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_ops_addon_purchases do |t|
      t.references :account, null: false, foreign_key: true
      t.string :pack_key, null: false
      t.integer :units, null: false
      t.integer :price_zar, null: false
      t.string :paystack_reference, null: false
      t.string :status, null: false, default: 'pending'
      t.timestamps
    end
    add_index :ai_ops_addon_purchases, :paystack_reference, unique: true
  end
end
