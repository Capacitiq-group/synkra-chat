class AddExtraSeatsBilledForReferenceToSynkraSubscriptions < ActiveRecord::Migration[7.2]
  # Idempotency guard for automatic extra-seat re-billing at each plan
  # renewal - see Billing::PaystackWebhookHandler#bill_extra_seats_for_renewal.
  # Paystack redelivers webhooks on retry, and start_new_period! itself
  # has no natural way to detect "this is the same renewal event fired
  # twice" (it just stamps Time.current each call) - extra-seat billing
  # needs its own guard because, unlike a duplicate start_new_period!
  # call (merely resets a clock), a duplicate charge_authorization call
  # actually charges the customer's card a second time.
  #
  # Keyed on the RENEWAL charge's own Paystack transaction reference
  # (unique per real transaction; webhook retries resend the same
  # reference rather than generating a new one), not on
  # current_period_start, which changes every call and so can't
  # distinguish a genuine new period from a redelivered webhook for the
  # same one.
  def change
    add_column :synkra_subscriptions, :extra_seats_billed_for_reference, :string
  end
end
