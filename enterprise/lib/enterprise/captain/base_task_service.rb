module Enterprise::Captain::BaseTaskService
  def perform
    return synkra_ai_credits_exhausted_error if counts_toward_usage? && !synkra_ai_credits_available?
    unless captain_tasks_enabled?
      return { error: I18n.t('captain.upgrade') } if ChatwootApp.chatwoot_cloud?
      return { error: I18n.t('captain.disabled') }
    end
    result = super
    if counts_toward_usage? && successful_result?(result)
      increment_usage
      record_synkra_usage
    end
    result
  end
  private
  # Synkra Chat runs self-hosted but has real billing (see
  # app/models/synkra_subscription.rb). Chatwoot's own responses_available?
  # short-circuits to true unless ChatwootApp.chatwoot_cloud?, so its
  # captain_responses quota never fires here. We check Synkra's own
  # ai_ops allowance instead, sourced from SynkraUsageEvent via
  # SynkraSubscription#ai_ops_used / #ai_ops_allowance.
  #
  # Fails open: if the subscription record can't be read, the AI call
  # is allowed. A billing-infra hiccup must never lock a business out
  # of AI features - matches the codebase's existing philosophy
  # (SynkraSubscription, Message, AccountUser all fail open).
  #
  # Only fires for user-facing task services. Every internal operation
  # (ConversationCompletionService, OverviewSummaryService, HelpCenter
  # curation, widget tagline, translate, article writer, migration
  # classifiers, audience matcher) overrides counts_toward_usage? to
  # false and is unaffected. The AI Agent's auto-reply path is one of
  # those - inbound replies are never blocked by credit state.
  def synkra_ai_credits_available?
    subscription = account.synkra_subscription
    return true if subscription.blank?
    subscription.ai_ops_used.to_i < subscription.ai_ops_allowance.to_i
  end
  def synkra_ai_credits_exhausted_error
    Rails.logger.info(
      "[CAPTAIN][#{self.class.name}] Blocked for account #{account.id}: " \
      'out of AI credits'
    )
    { error: I18n.t('captain.synkra_ai_credits_exhausted'), error_code: 429 }
  end
  def successful_result?(result)
    result.is_a?(Hash) && result[:message].present? && !result[:error]
  end
  def increment_usage
    Rails.logger.info("[CAPTAIN][#{self.class.name}] Incrementing response usage for account #{account.id}")
    account.increment_response_usage
  end
  # Writes the Synkra billing ledger entry for this AI operation.
  # SynkraUsageEvent is Chat's source of truth (billing reads from this
  # table - see its model comment). Fired after a successful result
  # only, never on failure or credit-block.
  #
  # Fire-and-forget: a ledger write failure must never turn a working
  # AI response into an error for the user - matches the Copilot path
  # (see Captain::Copilot::ReplySuggestionService#create_reply_suggestion)
  # and Automations::UsageTracker's own fail-open contract.
  def record_synkra_usage
    SynkraUsageEvent.record!(
      account: account,
      resource_type: 'ai_request',
      source: event_name.to_s
    )
    Automations::UsageTracker.track_ai_op!(account)
  rescue StandardError => e
    Rails.logger.error(
      "[SynkraBilling] Failed to record ai_request usage for account #{account.id}: #{e.message}"
    )
  end
end
