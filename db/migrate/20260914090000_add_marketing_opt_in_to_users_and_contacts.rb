class AddMarketingOptInToUsersAndContacts < ActiveRecord::Migration[7.2]
  # Marketing/transactional email split (13-14 Sep 2026, Refilwe).
  # Audit of every existing mailer in this codebase found nothing
  # marketing/promotional - all transactional (replies, identity
  # verification, security alerts, billing/usage notices, setup
  # instructions) - so this isn't a split of existing mixed mail, it's
  # net-new consent infrastructure for marketing email that doesn't
  # exist yet, ahead of the ~20 Sep 2026 launch.
  #
  # Two distinct audiences, two distinct fields, deliberately not
  # shared: users.marketing_emails_opt_in is for Capacitiq's own
  # marketing to Chat account admins/agents (the businesses paying
  # Refilwe). contacts.marketing_opt_in is for a Chat BUSINESS's own
  # marketing to ITS end-customers - a completely different
  # relationship (Capacitiq isn't the sender or the data controller
  # there, the business is) using Chatwoot's existing Campaign feature
  # as the sending mechanism, not a new one.
  #
  # No token/expiry columns needed for unsubscribe links - both models
  # use Rails' built-in signed_id (no new schema, self-expiring or not
  # as needed, no lookup required to verify).
  #
  # Default false on both: this codebase takes the more conservative
  # posture (explicit opt-in required) rather than assuming a
  # POPIA "existing customer" soft opt-in exemption applies - not
  # legal advice, worth confirming with someone qualified before
  # relying on it, especially for the contacts.marketing_opt_in case
  # where Capacitiq is providing infrastructure for its OWN customers
  # to market to THEIR customers.
  def change
    add_column :users, :marketing_emails_opt_in, :boolean, default: false, null: false
    add_column :contacts, :marketing_opt_in, :boolean, default: false, null: false
  end
end
