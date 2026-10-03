# Deducts from the single shared Automations credit balance (see
# docs/synkra/automations-flow-bridge.md) whenever Chat itself consumes
# something Flow meters - right now just Synkra AI Agent (Captain)
# replies, kind "ai_ops".
#
# Deliberately fail-open and fire-and-forget, matching this codebase's
# established pattern for billing-adjacent background work (see
# SynkraSubscription#sync_flow_plan!'s comment, and
# Captain::Conversation::ResponseBuilderJob#capture_assistant_session's
# "a session-logging bug must never roll back the customer reply").
# An AI reply has already been generated and sent by the time this
# runs - Automations tracking a business as slightly over their
# included allowance for a few minutes is a vastly smaller problem
# than blocking or delaying a customer-facing reply on Flow being
# reachable. This never raises into its caller.
module Automations::UsageTracker
  module_function

  def track_ai_op!(account)
    Automations::ConsumeCreditJob.perform_later(account.id, 'ai_ops', 1)
  end
end
