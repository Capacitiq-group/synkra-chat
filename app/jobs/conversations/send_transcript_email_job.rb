class Conversations::SendTranscriptEmailJob < ApplicationJob
  queue_as :low

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.nil?

    account = conversation.account
    return unless account.email_transcript_enabled?

    contact_email = conversation.contact&.email
    if contact_email.blank?
      Rails.logger.info(
        "[SynkraTranscript] Skipping conversation #{conversation.id} - no contact email"
      )
      return
    end

    subscription = account.synkra_subscription
    if subscription&.notification_emails_exhausted?
      Rails.logger.info(
        "[SynkraTranscript] Skipping conversation #{conversation.id} - notification email credits exhausted"
      )
      return
    end

    ConversationReplyMailer.with(account: account)
                           .conversation_transcript(conversation, contact_email)
                           &.deliver_later

    account.increment_email_sent_count
    record_transcript_email_usage(account)
  rescue StandardError => e
    Rails.logger.error(
      "[SynkraTranscript] Failed for conversation #{conversation_id}: #{e.class}: #{e.message}"
    )
  end

  private

  def record_transcript_email_usage(account)
    SynkraUsageEvent.record!(account: account, resource_type: 'email', source: 'conversation_transcript')
    account.synkra_subscription&.consume_purchased_notification_email_credit_if_over_plan_allowance!
  rescue StandardError => e
    Rails.logger.error(
      "[SynkraBilling] Failed to record email usage event for account #{account.id}: #{e.message}"
    )
  end
end
