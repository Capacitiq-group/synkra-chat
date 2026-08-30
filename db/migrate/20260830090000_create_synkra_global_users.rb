class CreateSynkraGlobalUsers < ActiveRecord::Migration[7.2]
  def change
    # Synkra Chat global identity layer: one row per real person, shared
    # across every business (Chatwoot account) they've ever chatted with.
    # Deliberately holds ONLY identity/auth data - no business-specific
    # information (name, preferences, tags, notes, etc. all stay on the
    # per-business Contact record, never here).
    create_table :synkra_global_users do |t|
      t.string :email, null: false
      t.datetime :email_verified_at

      # OTP is stored as a digest, never plaintext, same principle as a
      # password hash - even a DB read doesn't reveal a usable code.
      t.string :otp_digest
      t.datetime :otp_sent_at
      t.datetime :otp_expires_at
      t.integer :otp_attempts, null: false, default: 0

      t.timestamps
    end
    add_index :synkra_global_users, 'lower(email)', unique: true, name: 'index_synkra_global_users_on_lower_email'

    # Links each business's Contact record back to the one global person
    # it belongs to. Nullable: existing contacts are unlinked until they
    # next go through the identity flow: this is additive, not a backfill.
    add_column :contacts, :synkra_global_user_id, :bigint
    add_index :contacts, :synkra_global_user_id
  end
end
