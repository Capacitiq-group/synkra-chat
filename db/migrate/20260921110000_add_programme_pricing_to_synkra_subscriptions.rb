class AddProgrammePricingToSynkraSubscriptions < ActiveRecord::Migration[7.2]
  # Which discount programme ('student' / 'community') the account's
  # current Paystack subscription is priced under. Nil = standard
  # public price. The plan itself (starter/business/pro) is unchanged -
  # programmes only change what is charged, never the limits.
  def change
    add_column :synkra_subscriptions, :pricing_programme, :string
  end
end
