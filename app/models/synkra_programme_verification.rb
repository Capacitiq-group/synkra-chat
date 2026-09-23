# Synkra discount programmes: verification records for the Student
# programme (email code route or document route) and the Community
# Access programme (application + manual review). One row per attempt.
#
# Student eligibility lasts until the end of the calendar year it was
# verified in (South African time); Community Access lasts 12 months
# from approval. Both must be re-verified. No active verification =
# no programme billing.
class SynkraProgrammeVerification < ApplicationRecord
  PROGRAMMES = %w[student community].freeze
  # pending = email code sent, not yet entered; review = submitted and
  # waiting for a human; needs_info = reviewer asked for more evidence.
  STATUSES = %w[pending review needs_info rejected verified expired superseded].freeze
  METHODS = %w[email document application].freeze
  # Statuses that mean "an attempt is in flight" for an account/programme.
  OPEN_STATUSES = %w[pending review needs_info].freeze

  DOCUMENT_CONTENT_TYPES = %w[application/pdf image/jpeg image/png image/webp].freeze
  DOCUMENT_MAX_SIZE = 10.megabytes
  DOCUMENT_MAX_COUNT = 10

  # Offered as a dropdown in the UI - never free text - so the mailbox
  # domain always ends in one of these.
  STUDENT_EMAIL_EXTENSIONS = %w[ac.za edu edu.za ac.uk].freeze

  OTP_LENGTH = 6
  OTP_TTL = 10.minutes
  OTP_MAX_ATTEMPTS = 5
  OTP_RESEND_COOLDOWN = 60.seconds
  OTP_MAX_SENDS_PER_HOUR = 5

  ELIGIBILITY_TIME_ZONE = 'Africa/Johannesburg'.freeze

  # '+' is deliberately not allowed: name+1@uni.ac.za, name+2@uni.ac.za
  # would all reach one mailbox but look like different addresses.
  LOCAL_PART_FORMAT = /\A[a-z0-9]([a-z0-9._-]{0,62}[a-z0-9])?\z/
  INSTITUTION_FORMAT = /\A[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\z/

  belongs_to :account, optional: true
  belongs_to :user, optional: true
  # Student documents / Community evidence. Kept for the audit trail.
  has_many_attached :documents

  validates :programme, inclusion: { in: PROGRAMMES }
  validates :status, inclusion: { in: STATUSES }
  validates :verification_method, inclusion: { in: METHODS }
  validate :documents_are_acceptable

  scope :for_programme, ->(programme) { where(programme: programme) }

  def self.active_verification_for(account_id, programme)
    for_programme(programme)
      .where(account_id: account_id, status: 'verified')
      .where('expires_at > ?', Time.current)
      .order(verified_at: :desc)
      .first
  end

  def self.pending_for(account_id, programme)
    for_programme(programme)
      .where(account_id: account_id, status: 'pending')
      .order(created_at: :desc)
      .first
  end

  # The most recent attempt that is waiting on a person (either side).
  def self.open_review_for(account_id, programme)
    for_programme(programme)
      .where(account_id: account_id, status: %w[review needs_info])
      .order(created_at: :desc)
      .first
  end

  def self.generate_access_token
    loop do
      token = SecureRandom.alphanumeric(10).upcase
      break token unless where(access_token: token).exists?
    end
  end

  # A public application (no Synkra account yet - see /community-access)
  # ready to be attached to one: approved, unclaimed, not expired.
  def self.claimable(access_token)
    where(access_token: access_token, account_id: nil, status: 'verified')
      .where('expires_at > ?', Time.current)
      .first
  end

  # The programme an account is currently entitled to be billed under.
  # Community Access (60%) beats Student (35%) if both are active.
  def self.best_active_programme(account_id)
    %w[community student].find { |programme| active_verification_for(account_id, programme).present? }
  end

  # Returns [email, nil] or [nil, error_code].
  def self.compose_student_email(local_part:, institution:, extension:)
    local = local_part.to_s.strip.downcase
    institution = institution.to_s.strip.downcase.delete_prefix('@')
    extension = extension.to_s.strip.downcase.delete_prefix('.')

    return [nil, :invalid_extension] unless STUDENT_EMAIL_EXTENSIONS.include?(extension)
    return [nil, :invalid_local_part] unless local.match?(LOCAL_PART_FORMAT)
    return [nil, :invalid_institution] unless institution.length <= 120 && institution.match?(INSTITUTION_FORMAT)

    # "ukzn.ac.za" typed into the institution box would otherwise become
    # ukzn.ac.za.ac.za once the dropdown value is appended.
    if STUDENT_EMAIL_EXTENSIONS.any? { |ext| institution == ext || institution.end_with?(".#{ext}") }
      return [nil, :institution_includes_extension]
    end

    ["#{local}@#{institution}.#{extension}", nil]
  end

  def self.digest_for(record_id, code)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base, "programme-otp:#{record_id}:#{code}")
  end

  # Generates a fresh code, stores only its HMAC, and returns the
  # plaintext so the caller can email it. The plaintext is never saved.
  def issue_otp!
    code = format("%0#{OTP_LENGTH}d", SecureRandom.random_number(10**OTP_LENGTH))
    update!(
      otp_digest: self.class.digest_for(id, code),
      otp_sent_at: Time.current,
      otp_expires_at: OTP_TTL.from_now,
      otp_attempts: 0
    )
    code
  end

  # :ok | :invalid | :expired | :too_many_attempts | :not_pending
  def check_otp(code)
    return :not_pending unless status == 'pending'
    return :expired if otp_expires_at.blank? || otp_expires_at < Time.current
    return :too_many_attempts if otp_attempts >= OTP_MAX_ATTEMPTS

    # Count the attempt before comparing, so a crash mid-check can't
    # hand out a free guess.
    increment!(:otp_attempts)
    supplied = self.class.digest_for(id, code.to_s.strip)
    ActiveSupport::SecurityUtils.secure_compare(supplied, otp_digest.to_s) ? :ok : :invalid
  end

  def attempts_left
    [OTP_MAX_ATTEMPTS - otp_attempts, 0].max
  end

  def mark_verified!
    now = Time.current
    transaction do
      # Stale verified rows for this mailbox (expired by date but not yet
      # swept) would otherwise trip the unique index.
      if institution_email.present?
        self.class.where(institution_email: institution_email, status: 'verified')
            .where('expires_at <= ?', now).update_all(status: 'expired', updated_at: now)
      end
      # Public applications (account_id nil) are tracked individually by
      # access_token, not "one open attempt per account" - account_id is
      # NULL for every one of them, so a blanket account_id match here
      # would supersede unrelated applicants' rows too.
      unless account_id.nil?
        self.class.where(account_id: account_id, programme: programme, status: %w[verified] + OPEN_STATUSES)
            .where.not(id: id).update_all(status: 'superseded', updated_at: now)
      end
      update!(
        status: 'verified',
        verified_at: now,
        expires_at: eligibility_end(now),
        otp_digest: nil,
        otp_expires_at: nil
      )
    end
  end

  # Attaches a claimable public application to a real account (once the
  # organisation has created one), then prices it same as an in-app
  # approval would. One-time: clears access_token so it can't be reused.
  def claim!(account:, user:)
    update!(account_id: account.id, user_id: user.id, access_token: nil)
    Billing::ProgrammePricingService.new(account).apply!
  end

  # Reviewer outcomes (super admin) and automatic document approval.
  def approve!(reviewer:, note: nil)
    mark_verified!
    update!(reviewed_at: Time.current, reviewed_by: reviewer, review_note: note)
  end

  def reject!(reviewer:, note:)
    update!(status: 'rejected', reviewed_at: Time.current, reviewed_by: reviewer, review_note: note)
  end

  def request_info!(reviewer:, note:)
    update!(status: 'needs_info', reviewed_at: Time.current, reviewed_by: reviewer, review_note: note)
  end

  def student?
    programme == 'student'
  end

  def community?
    programme == 'community'
  end

  def public_application?
    account_id.nil?
  end

  private

  def eligibility_end(from)
    return from.in_time_zone(ELIGIBILITY_TIME_ZONE).end_of_year if student?

    from + 1.year
  end

  def documents_are_acceptable
    return unless documents.attached?

    errors.add(:documents, 'too many files') if documents.count > DOCUMENT_MAX_COUNT
    documents.each do |document|
      unless DOCUMENT_CONTENT_TYPES.include?(document.content_type)
        errors.add(:documents, 'must be a PDF, JPG, PNG or WebP file')
      end
      errors.add(:documents, 'must be 10 MB or smaller') if document.byte_size > DOCUMENT_MAX_SIZE
    end
  end
end
