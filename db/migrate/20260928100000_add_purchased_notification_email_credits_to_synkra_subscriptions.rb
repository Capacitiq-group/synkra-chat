class AddPurchasedNotificationEmailCreditsToSynkraSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :synkra_subscriptions, :purchased_notification_email_credits,
               :integer, default: 0, null: false
  end
end
