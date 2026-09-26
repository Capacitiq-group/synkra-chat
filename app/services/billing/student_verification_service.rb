# Student Programme, email route: the student enters their institution
# email (number @ institution + a fixed extension from a dropdown),
# we email a 6-digit code to that mailbox, and entering it proves they
# control an institutional address. See SynkraProgrammeVerification.
class Billing::StudentVerificationService
  PROGRAMME = 'student'.freeze

  Result = Struct.new(:success?, :code, :data, keyword_init: true)

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def send_code(local_part:, institution:, extension:)
    email, error = SynkraProgrammeVerification.compose_student_email(
      local_part: local_part, institution: institution, extension: extension
    )
    return failure(error) if error
    return failure(:already_verified) if SynkraProgrammeVerification.active_verification_for(@account.id, PROGRAMME)
    return failure(:email_in_use) if email_used_by_another_account?(email)

    limit_failure = check_send_limits
    return limit_failure if limit_failure

    verification, code = create_verification(email)

    begin
      Billing::ProgrammeMailer.student_code(verification: verification, code: code).deliver_now
    rescue StandardError => e
      Rails.logger.error "[SynkraProgramme] Couldn't send student code (verification #{verification.id}): #{e.class}"
      verification.update!(status: 'superseded')
      return failure(:delivery_failed)
    end

    Result.new(success?: true, data: { email: email })
  end

  def confirm(code:)
    supplied = code.to_s.strip
    return failure(:invalid_code) unless supplied.match?(/\A\d{#{SynkraProgrammeVerification::OTP_LENGTH}}\z/)

    verification = SynkraProgrammeVerification.pending_for(@account.id, PROGRAMME)
    return failure(:no_pending) if verification.nil?

    case verification.check_otp(supplied)
    when :ok
      verification.mark_verified!
      Billing::ProgrammePricingService.new(@account).apply!
      Result.new(success?: true, data: { verification: verification })
    when :invalid then failure(:invalid_code, attempts_left: verification.attempts_left)
    when :expired then failure(:code_expired)
    when :too_many_attempts then failure(:too_many_attempts)
    else failure(:no_pending)
    end
  rescue ActiveRecord::RecordNotUnique
    failure(:email_in_use)
  end

  # Document route: the student uploads proof of current enrolment
  # instead of using an institution email. Read automatically where
  # possible (Billing::ProgrammeDocumentReviewJob); anything doubtful
  # goes to manual review, so this only ever queues the submission.
  MAX_DOCUMENT_SUBMISSIONS_PER_DAY = 5

  def submit_document(files:)
    files = Array(files).select { |file| file.respond_to?(:content_type) && file.respond_to?(:size) }
    return failure(:no_files) if files.empty?
    return failure(:too_many_files) if files.size > SynkraProgrammeVerification::DOCUMENT_MAX_COUNT
    return failure(:invalid_file_type) unless files.all? { |f| SynkraProgrammeVerification::DOCUMENT_CONTENT_TYPES.include?(f.content_type) }
    return failure(:file_too_large) if files.any? { |f| f.size > SynkraProgrammeVerification::DOCUMENT_MAX_SIZE }
    return failure(:already_verified) if SynkraProgrammeVerification.active_verification_for(@account.id, PROGRAMME)

    recent = SynkraProgrammeVerification.for_programme(PROGRAMME)
                                        .where(account_id: @account.id, verification_method: 'document')
                                        .where('created_at > ?', 24.hours.ago).count
    return failure(:rate_limited) if recent >= MAX_DOCUMENT_SUBMISSIONS_PER_DAY

    verification = SynkraProgrammeVerification.transaction do
      SynkraProgrammeVerification.for_programme(PROGRAMME)
                                 .where(account_id: @account.id, status: SynkraProgrammeVerification::OPEN_STATUSES)
                                 .update_all(status: 'superseded', updated_at: Time.current)
      record = SynkraProgrammeVerification.create!(
        account_id: @account.id, user_id: @user.id, programme: PROGRAMME,
        verification_method: 'document', status: 'review', submitted_at: Time.current
      )
      record.documents.attach(files)
      record
    end

    Billing::ProgrammeDocumentReviewJob.perform_later(verification.id)
    Result.new(success?: true, data: { verification: verification })
  end

  private

  def failure(code, data = {})
    Result.new(success?: false, code: code, data: data)
  end

  def email_used_by_another_account?(email)
    SynkraProgrammeVerification.for_programme(PROGRAMME)
                               .where(institution_email: email, status: 'verified')
                               .where('expires_at > ?', Time.current)
                               .where.not(account_id: @account.id)
                               .exists?
  end

  # Every send creates a new row, so the rows themselves are the counter.
  def check_send_limits
    recent = SynkraProgrammeVerification.for_programme(PROGRAMME).where(account_id: @account.id)

    last_sent_at = recent.maximum(:otp_sent_at)
    if last_sent_at && last_sent_at > SynkraProgrammeVerification::OTP_RESEND_COOLDOWN.ago
      retry_after = (last_sent_at + SynkraProgrammeVerification::OTP_RESEND_COOLDOWN - Time.current).ceil
      return failure(:cooldown, retry_after: retry_after)
    end

    sends_last_hour = recent.where('created_at > ?', 1.hour.ago).count
    return failure(:rate_limited) if sends_last_hour >= SynkraProgrammeVerification::OTP_MAX_SENDS_PER_HOUR

    nil
  end

  def create_verification(email)
    verification = nil
    code = nil
    SynkraProgrammeVerification.transaction do
      SynkraProgrammeVerification.for_programme(PROGRAMME)
                                 .where(account_id: @account.id, status: 'pending')
                                 .update_all(status: 'superseded', updated_at: Time.current)
      verification = SynkraProgrammeVerification.create!(
        account_id: @account.id, user_id: @user.id, programme: PROGRAMME,
        verification_method: 'email', institution_email: email
      )
      code = verification.issue_otp!
    end
    [verification, code]
  end
end
