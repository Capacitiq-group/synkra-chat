module Captain::ChatResponseHelper
  include Integrations::LlmInstrumentationConstants

  private

  def build_response(response)
    Rails.logger.debug { "#{self.class.name} Assistant: #{@assistant.id}, Received response #{response}" }
    parsed = parse_json_response(response.content)
    apply_credit_usage_metadata(parsed)

    # A blank/unparseable response from the LLM used to reach
    # persist_message and blow up with ActiveRecord::RecordInvalid
    # ("Message can't be blank"), which killed the job and left the
    # Copilot UI waiting forever for a broadcast that never came.
    # Surface the failure as a real assistant message instead, so the UI
    # renders an error and the loading state clears.
    return persist_empty_response_warning(response) if blank_response?(parsed)

    persist_message(parsed, 'assistant')
    parsed
  end

  def blank_response?(parsed)
    return true if parsed.blank?
    return false unless parsed.is_a?(Hash)

    parsed['content'].blank? && parsed['response'].blank?
  end

  def persist_empty_response_warning(response)
    Rails.logger.warn(
      "#{self.class.name} Assistant: #{@assistant.id}, " \
      "LLM returned no usable content (raw=#{response.content.to_s.truncate(200).inspect}). " \
      "Persisting a user-visible failure message instead of an empty record."
    )
    persist_message(
      { 'content' => "I wasn't able to generate a response just now. Please try again." },
      'assistant'
    )
    { 'content' => '' }
  end

  def parse_json_response(content)
    return {} if content.blank?

    content = content.gsub('```json', '').gsub('```', '')
    content = content.strip
    JSON.parse(content)
  rescue JSON::ParserError => e
    Rails.logger.error "#{self.class.name} Assistant: #{@assistant.id}, Error parsing JSON response: #{e.message}"
    { 'content' => content }
  end

  def apply_credit_usage_metadata(parsed_response)
    return unless captain_v1_assistant?

    OpenTelemetry::Trace.current_span.set_attribute(
      format(ATTR_LANGFUSE_METADATA, 'credit_used'),
      credit_used_for_response?(parsed_response).to_s
    )
  rescue StandardError => e
    Rails.logger.warn "#{self.class.name} Assistant: #{@assistant.id}, Failed to set credit usage metadata: #{e.message}"
  end

  def credit_used_for_response?(parsed_response)
    response = parsed_response['response']
    # The classifier can still decide to hand off after this trace is written.
    # Actual response usage is charged later in ResponseBuilderJob, so billing stays correct.
    response.present? && response != 'conversation_handoff' && parsed_response['action'] != 'handoff'
  end

  def captain_v1_assistant?
    feature_name == 'assistant' && !@assistant.account.feature_enabled?('captain_integration_v2')
  end

  def persist_thinking_message(tool_call)
    return if @copilot_thread.blank?

    tool_name = tool_call.name.to_s
    persist_message(
      {
        'content' => "Using #{tool_name}",
        'function_name' => tool_name
      },
      'assistant_thinking'
    )
  end

  def persist_tool_completion
    return if @copilot_thread.blank?

    tool_call = @pending_tool_calls&.pop
    return unless tool_call

    tool_name = tool_call.name.to_s
    persist_message(
      {
        'content' => "Completed #{tool_name}",
        'function_name' => tool_name
      },
      'assistant_thinking'
    )
  end
end
