class AddFlowPlanSyncedAtToSynkraSubscriptions < ActiveRecord::Migration[7.2]
  # Lets Automations::ReconcileFlowPlanJob detect a plan change whose
  # Automations::SyncFlowPlanJob never landed on Flow (exhausted retries,
  # or the job was enqueued but the process died before it ran) - see
  # SynkraSubscription#plan_sync_stale? and
  # docs/synkra/automations-flow-bridge.md.
  #
  # plan_changed_at is deliberately separate from the generic updated_at
  # column: the same update! call that stamps flow_plan_synced_at also
  # bumps updated_at, so comparing against updated_at would make a
  # subscription look "stale again" immediately after a successful sync,
  # depending on statement-internal timestamp ordering.
  def change
    add_column :synkra_subscriptions, :flow_plan_synced_at, :datetime
    add_column :synkra_subscriptions, :plan_changed_at, :datetime
  end
end
