# Kimi (Moonshot AI) API - used only to read student verification
# documents. Requires KIMI_API_KEY; KIMI_API_BASE_URL and KIMI_MODEL
# are optional overrides (Moonshot rotates its model lineup, so the
# model name is configuration, not code).
#
# Every method returns a Result instead of raising, and callers treat
# any failure as "send to manual review" - a Kimi outage or a bad
# response can never approve (or reject) anyone on its own.
class Billing::KimiClient
  Result = Struct.new(:success?, :data, :error, keyword_init: true)

  DEFAULT_BASE_URL = 'https://api.moonshot.ai/v1'.freeze
  DEFAULT_MODEL = 'kimi-k2.6'.freeze
  MAX_TEXT_CHARS = 12_000

  PROMPT = <<~TEXT.freeze
    You are checking a document that someone uploaded to prove they are currently enrolled at a higher-education institution.
    Extract facts ONLY from the document itself. Do not guess or infer anything that is not visible.
    Reply with ONLY a JSON object, no other text, with exactly these keys:
    {
      "document_type": one of "transcript", "registration", "fee_statement", "enrolment_confirmation", "student_card", "other",
      "institution_name": string or null,
      "student_full_name": string or null (exactly as printed),
      "issue_date": "YYYY-MM-DD" or null (the date the document was issued or generated),
      "academic_year": integer or null,
      "shows_current_enrolment": true or false (does the document itself state the person is currently registered or enrolled),
      "has_institution_branding": true or false (official letterhead, logo or clearly institutional layout),
      "appears_altered": true or false (obvious edits, mismatched fonts, pasted-in text, or the file is a screenshot of a chat or web page),
      "notes": one short sentence, at most 200 characters
    }
  TEXT

  def initialize
    @api_key = ENV.fetch('KIMI_API_KEY', nil)
    @base_url = ENV.fetch('KIMI_API_BASE_URL', DEFAULT_BASE_URL)
    @model = ENV.fetch('KIMI_MODEL', DEFAULT_MODEL)
  end

  def configured?
    @api_key.present?
  end

  # bytes + content_type of an uploaded image, or text extracted from a PDF.
  def extract_from_image(bytes, content_type)
    content = [
      { type: 'image_url', image_url: { url: "data:#{content_type};base64,#{Base64.strict_encode64(bytes)}" } },
      { type: 'text', text: PROMPT }
    ]
    request(content)
  end

  def extract_from_text(text)
    request("#{PROMPT}\n\nDocument text:\n#{text.to_s.first(MAX_TEXT_CHARS)}")
  end

  private

  def request(content)
    return Result.new(success?: false, error: 'Kimi is not configured') unless configured?

    body = { model: @model, messages: [{ role: 'user', content: content }] }
    # K2.x models think by default (slow, and the reasoning is not
    # needed to read a document); K3 always reasons and may reject the flag.
    body[:thinking] = { type: 'disabled' } unless @model.start_with?('kimi-k3')

    response = post_chat(body)
    if response.status == 400 && body.key?(:thinking)
      body.delete(:thinking)
      response = post_chat(body)
    end
    return Result.new(success?: false, error: "Kimi returned HTTP #{response.status}") unless response.success?

    parse(response.body.dig('choices', 0, 'message', 'content'))
  rescue StandardError => e
    Result.new(success?: false, error: "#{e.class}: #{e.message}")
  end

  def post_chat(body)
    connection.post('chat/completions') { |req| req.body = body }
  end

  def parse(text)
    json = text.to_s[/\{.*\}/m]
    return Result.new(success?: false, error: 'No JSON in Kimi response') if json.blank?

    Result.new(success?: true, data: JSON.parse(json))
  rescue JSON::ParserError
    Result.new(success?: false, error: 'Unparseable JSON in Kimi response')
  end

  def connection
    @connection ||= Faraday.new(url: "#{@base_url.chomp('/')}/") do |f|
      f.request :json
      f.response :json, content_type: /\bjson$/
      f.headers['Authorization'] = "Bearer #{@api_key}"
      f.options.timeout = 180
      f.options.open_timeout = 15
      f.adapter Faraday.default_adapter
    end
  end
end
