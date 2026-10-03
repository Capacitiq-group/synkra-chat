class AddReviewFieldsToSynkraProgrammeVerifications < ActiveRecord::Migration[7.2]
  # Supports the document route (Student) and the Community Access
  # application: application_data holds the applicant's form answers,
  # ocr_result the structured fields extracted from a submitted
  # document (never the raw document text), review_* the outcome of a
  # manual review, expiry_warning_days the last "expires soon" email sent.
  def change
    change_table :synkra_programme_verifications, bulk: true do |t|
      t.jsonb :application_data, null: false, default: {}
      t.jsonb :ocr_result, null: false, default: {}
      t.datetime :submitted_at
      t.datetime :reviewed_at
      t.string :reviewed_by
      t.text :review_note
      t.integer :expiry_warning_days
    end

    add_index :synkra_programme_verifications, %i[programme status],
              name: 'idx_programme_verifications_programme_status'
  end
end
