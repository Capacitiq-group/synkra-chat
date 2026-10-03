# Extracts text (markdown-ish for DOCX, plain text for PDF) from an
# uploaded Captain::Document's pdf_file attachment, for writing
# straight into Document#content - the same field/pipeline website
# crawls already use for embeddings. Deliberately NOT the same thing
# as Chatwoot's own Captain::Llm::PdfProcessingService, which uploads
# the raw file to OpenAI's Files API and relies on OpenAI's own hosted
# file-search - that never worked against our self-hosted Ollama setup
# (confirmed by reading that service's code: it never sets #content at
# all, only an openai_file_id).
#
# Pure-Ruby (pdf-reader, docx gem) by design - no system binary
# (poppler/pandoc) dependency, smaller security surface for files a
# customer uploaded. Tradeoffs, stated plainly:
# - PDFs have no reliable semantic structure to convert to markdown.
#   This extracts text page-by-page; it is not a structural
#   conversion, just the honest best effort. Scanned/image-only PDFs
#   extract nothing (no OCR) - callers should treat empty extraction
#   as a real possibility, not a bug.
# - DOCX has real structure (heading/list styles) and converts to
#   markdown more meaningfully.
# - Zip-bomb risk for DOCX (a .docx is a zip of XML) is bounded by the
#   existing 10MB upload cap and the timeout below, not eliminated -
#   this doesn't reimplement rubyzip's decompression-ratio checks.
# - XXE: relies on Nokogiri's secure-by-default external-entity
#   handling (the docx gem parses its internal XML via Nokogiri, which
#   has not resolved external entities by default for years) rather
#   than configuring it directly, since the docx gem's own Nokogiri
#   usage isn't something this service can pass parse options into.
class Captain::Documents::TextExtractionService
  MAX_PROCESSING_SECONDS = 60
  # Matches Captain::Document's own `validates :content, length:
  # {maximum: 200_000}` - truncate here rather than let that
  # validation reject an otherwise-successful extraction outright.
  MAX_CONTENT_LENGTH = 200_000

  class ExtractionError < StandardError; end

  def initialize(document)
    @document = document
  end

  def extract
    Timeout.timeout(MAX_PROCESSING_SECONDS) do
      text = @document.pdf_document? ? extract_pdf : extract_docx
      text.to_s.strip.truncate(
        MAX_CONTENT_LENGTH,
        omission: "\n\n[Content truncated - the original document was longer than fits here]"
      )
    end
  rescue Timeout::Error
    raise ExtractionError, "timed out after #{MAX_PROCESSING_SECONDS}s"
  rescue ExtractionError
    raise
  rescue StandardError => e
    raise ExtractionError, e.message
  end

  private

  def extract_pdf
    text_parts = []
    @document.pdf_file.blob.open do |file|
      reader = PDF::Reader.new(file)
      reader.pages.each do |page|
        page_text = page.text.to_s.strip
        text_parts << page_text if page_text.present?
      end
    end
    # Page separator, not a claim of real document structure - see the
    # class comment above on why PDF can't reliably become markdown.
    text_parts.join("\n\n---\n\n")
  end

  def extract_docx
    lines = []
    @document.pdf_file.blob.open do |file|
      doc = Docx::Document.open(file)
      doc.paragraphs.each do |paragraph|
        text = paragraph.to_s.strip
        next if text.blank?

        lines << markdown_line_for(paragraph, text)
      end
    end
    lines.join("\n\n")
  end

  def markdown_line_for(paragraph, text)
    heading_level = heading_level_for(paragraph)
    return "#{'#' * heading_level} #{text}" if heading_level
    return "- #{text}" if list_item?(paragraph)

    text
  end

  # Style names can come back with or without a space ("Heading1" vs
  # "Heading 1") depending on the document's origin - matched
  # tolerantly rather than assumed. Never lets a style-detection
  # hiccup break extraction: falls back to a plain paragraph.
  def heading_level_for(paragraph)
    match = paragraph.style.to_s.match(/\AHeading\s*([1-6])\z/i)
    match && match[1].to_i
  rescue StandardError
    nil
  end

  def list_item?(paragraph)
    paragraph.style.to_s.match?(/\AList/i)
  rescue StandardError
    false
  end
end
