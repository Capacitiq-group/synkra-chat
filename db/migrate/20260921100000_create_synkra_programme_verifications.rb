# Synkra discount programmes (Student now, Community Access later).
# One row per verification attempt: every "send code" creates a fresh
# row (older pending rows are marked superseded), so the same table
# doubles as the audit trail and as the per-hour send counter.
class CreateSynkraProgrammeVerifications < ActiveRecord::Migration[7.2]
  def change
    create_table :synkra_programme_verifications do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.string :programme, null: false
      t.string :verification_method, null: false, default: 'email'
      t.string :status, null: false, default: 'pending'
      t.string :institution_email
      t.string :otp_digest
      t.datetime :otp_sent_at
      t.datetime :otp_expires_at
      t.integer :otp_attempts, null: false, default: 0
      t.datetime :verified_at
      t.datetime :expires_at
      t.timestamps
    end

    add_index :synkra_programme_verifications, %i[account_id programme status],
              name: 'idx_programme_verifications_account_programme_status'

    # One live student verification per institutional mailbox, across
    # all accounts. Superseded/expired rows fall outside the index, so
    # a student can reverify next year with the same address.
    add_index :synkra_programme_verifications, :institution_email,
              unique: true,
              where: "status = 'verified' AND programme = 'student'",
              name: 'idx_programme_verifications_unique_verified_student_email'
  end
end
