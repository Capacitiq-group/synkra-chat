class Api::V1::Accounts::Captain::TasksController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :extend_request_timeout_for_llm

  def rewrite
    result = Captain::RewriteService.new(
      account: Current.account,
      content: params[:content],
      operation: params[:operation],
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  def summarize
    result = Captain::SummaryService.new(
      account: Current.account,
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  def reply_suggestion
    result = Captain::ReplySuggestionService.new(
      account: Current.account,
      conversation_display_id: params[:conversation_display_id],
      user: Current.user
    ).perform

    render_result(result)
  end

  def label_suggestion
    result = Captain::LabelSuggestionService.new(
      account: Current.account,
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  def follow_up
    result = Captain::FollowUpService.new(
      account: Current.account,
      follow_up_context: params[:follow_up_context]&.to_unsafe_h,
      user_message: params[:message],
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  private

  def render_result(result)
    if result.nil?
      render json: { message: nil }
    elsif result[:error]
      render json: { error: result[:error] }, status: :unprocessable_content
    else
      response_data = { message: result[:message] }
      response_data[:follow_up_context] = result[:follow_up_context] if result[:follow_up_context]
      render json: response_data
    end
  end

  def check_authorization
    authorize(:'captain/tasks')
  end

  # All 5 actions above call an LLM inline and wait for the result -
  # Rack::Timeout's default 15s service_timeout is far too tight for
  # CPU-based local inference (confirmed 24 Sep 2026: a real,
  # in-progress "summarize" call was killed by this default before
  # Ollama finished generating - not a bad/failed response, a request
  # that was still legitimately working). Copilot's equivalent actions
  # aren't affected by this at all since they run via perform_later
  # (Sidekiq), outside the Rack request cycle entirely.
  def extend_request_timeout_for_llm
    request.env['rack-timeout.info']&.service_timeout = 60
  end
end

Api::V1::Accounts::Captain::TasksController.prepend_mod_with('Api::V1::Accounts::Captain::TasksController')
