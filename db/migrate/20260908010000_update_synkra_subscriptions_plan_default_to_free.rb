class UpdateSynkraSubscriptionsPlanDefaultToFree < ActiveRecord::Migration[7.1]
  # 'basic' was retired when the real four-tier plan structure (free /
  # starter / business / pro) replaced it - see SynkraPlan. Existing
  # rows are untouched here (accounts already got backfilled to 'free'
  # via Account#provision_synkra_subscription / Message's fallback
  # directly against the DB, not by relying on this default), this
  # only fixes the column default for any future row created without
  # an explicit plan.
  def change
    change_column_default :synkra_subscriptions, :plan, from: 'basic', to: 'free'
  end
end
