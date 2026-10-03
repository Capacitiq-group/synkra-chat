# Reads a submitted student document with Kimi, applies Synkra's rules
# (Billing::StudentDocumentRules) and either approves automatically
# (every rule passed) or leaves it in the manual review queue with the
# findings attached. Only structured fields are stored - never the
# document's raw text. Any failure (Kimi down, scanned PDF with no
# text, unreadable response) also lands in the manual queue.
class Billing::ProgrammeDocumentReviewJob < ApplicationJob
  queue_as :default

  def perform(verification_id)
    verification = SynkraProgrammeVerification.find_by(id: verification_id)
    return unless verification&.status == 'review' && verification.verification_method == 'document' && verification.student?

    facts = read_document(verification)
    if facts.nil?
      verification.update!(ocr_result: { 'status' => 'manual_review', 'reasons' => ['automatic_check_unavailable'] })
      Billing::ProgrammeMailer.review_requested(verification: verification).deliver_later
      return
    end

    reasons = Billing::StudentDocumentRules.check(facts, account_name: verification.user.name)
    verification.update!(ocr_result: facts.merge('reasons' => reasons))

    if reasons.empty?
      verification.approve!(reviewer: 'automatic')
      Billing::ProgrammePricingService.new(verification.account).apply!
      Billing::ProgrammeMailer.review_outcome(verification: verification, outcome: 'approved').deliver_later
    else
      Billing::ProgrammeMailer.review_requested(verification: verification).deliver_later
    end
  end

  private

  # A student may upload several files (e.g. a transcript and a fee
  # statement); the first one that reads cleanly is used.
  def read_document(verification)
    client = Billing::KimiClient.new
    return nil unless client.configured?

    verification.documents.each do |document|
      result = read_one(client, document)
      return result.data if result&.success?
    end
    nil
  end

  def read_one(client, document)
    if document.content_type == 'application/pdf'
      text = pdf_text(document.download)
      return nil if text.blank?

      client.extract_from_text(text)
    else
      client.extract_from_image(document.download, document.content_type)
    end
  end

  def pdf_text(bytes)
    reader = PDF::Reader.new(StringIO.new(bytes))
    reader.pages.first(5).map(&:text).join("\n").strip
  rescue StandardError => e
    Rails.logger.warn "[SynkraProgramme] Couldn't read PDF text: #{e.class}"
    nil
  end
end
