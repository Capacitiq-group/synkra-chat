class AddPurchasedExtraSeatsToSynkraSubscriptions < ActiveRecord::Migration[7.2]
  # Extra seats beyond a plan's staff_limit: R69/seat/month (confirmed
  # by Refilwe 13 Sep 2026 - SynkraPlan::EXTRA_SEAT_PRICE_ZAR). See
  # Api::V1::Accounts::Billing::ExtraSeatsController for the purchase
  # flow and Billing::PaystackWebhookHandler#bill_extra_seats_for_renewal
  # for the recurring monthly re-charge.
  def change
    add_column :synkra_subscriptions, :purchased_extra_seats, :integer, default: 0, null: false
  end
end
