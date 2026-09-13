class AddPurchasedExtraSeatsToSynkraSubscriptions < ActiveRecord::Migration[7.2]
  # Extra seats beyond a plan's staff_limit: R69/seat/month (confirmed
  # by Refilwe 13 Sep 2026 - SynkraPlan::EXTRA_SEAT_PRICE_ZAR). See
  # Billing::ExtraSeatsController and the caveat in that file about
  # recurring re-billing NOT being built yet - only the initial
  # purchase charge is.
  def change
    add_column :synkra_subscriptions, :purchased_extra_seats, :integer, default: 0, null: false
  end
end
