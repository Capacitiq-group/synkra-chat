# Synkra's own eligibility rules for a student document. The OCR/vision
# model only READS the document (Billing::KimiClient); whether it
# qualifies is decided here, so the rules stay ours. Returns a list of
# reason codes - empty means every rule passed.
#
# Never used to reject anyone outright: any reason sends the document
# to a person (see Billing::ProgrammeDocumentReviewJob).
class Billing::StudentDocumentRules
  ACCEPTED_TYPES = %w[transcript registration fee_statement enrolment_confirmation].freeze

  def self.check(facts, account_name:, now: Time.current)
    reasons = []
    facts = (facts || {}).to_h.stringify_keys

    reasons << type_reason(facts['document_type'])
    reasons << 'institution_missing' if facts['institution_name'].to_s.strip.blank?
    reasons << 'name_mismatch' unless same_name?(facts['student_full_name'], account_name)
    reasons << 'not_current_year' unless current_year?(facts, now)
    reasons << 'enrolment_not_shown' unless facts['shows_current_enrolment'] == true
    reasons << 'branding_missing' unless facts['has_institution_branding'] == true
    reasons << 'possible_alteration' if facts['appears_altered'] == true

    reasons.compact
  end

  def self.type_reason(document_type)
    return nil if ACCEPTED_TYPES.include?(document_type)

    document_type == 'student_card' ? 'student_card_not_accepted' : 'document_type_unclear'
  end

  # Must match the SYNKRA account name exactly, ignoring case, accents,
  # punctuation, spacing and word order ("DLAMINI Refilwe" = "Refilwe Dlamini").
  def self.same_name?(document_name, account_name)
    normalized_tokens(document_name).present? && normalized_tokens(document_name) == normalized_tokens(account_name)
  end

  def self.normalized_tokens(name)
    ActiveSupport::Inflector.transliterate(name.to_s).downcase.gsub(/[^a-z\s]/, ' ').split.sort
  end

  def self.current_year?(facts, now)
    year = year_from(facts['issue_date']) || facts['academic_year'].to_i
    year == now.in_time_zone(SynkraProgrammeVerification::ELIGIBILITY_TIME_ZONE).year
  end

  def self.year_from(date_string)
    Date.iso8601(date_string.to_s).year
  rescue ArgumentError
    nil
  end
end
