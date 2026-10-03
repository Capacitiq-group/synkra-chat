class AddPaystackAuthorizationCodeToSynkraSubscriptions < ActiveRecord::Migration[7.1]
  # Needed to actually sync a downgrade to Paystack (see
  # Billing::PaystackWebhookHandler#swap_paystack_plan_if_pending!):
  # creating a replacement subscription on the new (lower) plan
  # requires a stored card/direct-debit authorization, since Paystack
  # never lets you charge a customer without one on file.
  def change
    add_column :synkra_subscriptions, :paystack_authorization_code, :string
  end
end
