class AddPreferredCurrencyToSynkraSubscriptions < ActiveRecord::Migration[7.2]
  def change
    # Display-only preference - the actual Paystack charge is always in
    # ZAR regardless of this value (Paystack settles ZAR into Synkra's
    # SA bank account; the customer's own card issuer handles real
    # currency conversion for international cards). This column only
    # controls which currency Chat's own UI shows prices in.
    add_column :synkra_subscriptions, :preferred_currency, :string, default: 'zar', null: false
  end
end
