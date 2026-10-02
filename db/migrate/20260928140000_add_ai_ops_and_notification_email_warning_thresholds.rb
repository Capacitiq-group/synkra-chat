class AddAiOpsAndNotificationEmailWarningThresholds < ActiveRecord::Migration[7.2]
  def change
    add_column :synkra_subscriptions, :last_ai_ops_warning_threshold, :decimal
    add_column :synkra_subscriptions, :last_notification_email_warning_threshold, :decimal
  end
end
