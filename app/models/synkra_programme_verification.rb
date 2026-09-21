# Synkra discount programmes: verification records. Only the Student
# programme's email route exists so far; Community Access and the
# document route reuse this table (programme / verification_method).
#
# Student eligibility lasts until the end of the calendar year it was
# verified in (South African time) and must be re-verified every year.
# No active verification = no student billing.
class SynkraProgrammeVerification < ApplicationRecord
  PROGRAMMES = %w[student].freeze
  STATUSES = %w[pending verified expired superseded].freeze

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

  belongs_to :account
  belongs_to :user

  validates :programme, inclusion: { in: PROGRAMMES }
  validates :status, inclusion: { in: STATUSES }

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
      self.class.where(institution_email: institution_email, status: 'verified')
          .where('expires_at <= ?', now).update_all(status: 'expired', updated_at: now)
      self.class.where(account_id: account_id, programme: programme, status: %w[verified pending])
          .where.not(id: id).update_all(status: 'superseded', updated_at: now)
      update!(
        status: 'verified',
        verified_at: now,
        expires_at: now.in_time_zone(ELIGIBILITY_TIME_ZONE).end_of_year,
        otp_digest: nil,
        otp_expires_at: nil
      )
    end
  end
end
