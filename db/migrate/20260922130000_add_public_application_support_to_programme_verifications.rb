# Lets a Community Access application exist before there's a Synkra
# account to attach it to - the public form at /community-access has
# no login, so account_id/user_id aren't known yet at submission.
class AddPublicApplicationSupportToProgrammeVerifications < ActiveRecord::Migration[7.2]
  def change
    change_column_null :synkra_programme_verifications, :account_id, true
    change_column_null :synkra_programme_verifications, :user_id, true

    change_table :synkra_programme_verifications, bulk: true do |t|
      t.string :contact_email
      # One code that works for status checks before a decision, replies
      # to a reviewer's "need more info", and - once approved - claiming
      # the discount onto a real account. Generated at submission, so
      # it's always present for a public application; nil for the
      # existing in-app flow.
      t.string :access_token
    end

    add_index :synkra_programme_verifications, :access_token, unique: true, where: 'access_token IS NOT NULL'
  end
end
