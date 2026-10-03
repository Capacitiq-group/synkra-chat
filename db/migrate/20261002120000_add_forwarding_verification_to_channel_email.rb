class AddForwardingVerificationToChannelEmail < ActiveRecord::Migration[7.2]
  def change
    add_column :channel_email, :forwarding_verification_pending_at, :datetime
    add_column :channel_email, :forwarding_verification_completed_at, :datetime
  end
end
