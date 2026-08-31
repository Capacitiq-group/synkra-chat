# Synkra Chat global identity layer.
#
# One row per real person, shared across every business (Chatwoot
# account) they've ever chatted with. Deliberately holds ONLY
# identity/authentication data. Business-specific information (name,
# preferences, tags, notes, conversation history, memory, etc.) always
# lives on the per-business Contact record, never here - Contact#
# synkra_global_user_id is the only link between the two, and nothing
# should ever be copied up onto this model from a business context.
class SynkraGlobalUser < ApplicationRecord
  OTP_LENGTH = 6
  OTP_VALID_FOR = 10.minutes
  MAX_OTP_ATTEMPTS = 5
  # Minimum gap between OTP sends, so the endpoint can't be used to spam
  # someone's inbox or rack up mail-sending costs.
  OTP_RESEND_COOLDOWN = 30.seconds
  # How long a device stays "trusted" (skips OTP) after a successful
  # verification, via the signed cookie set by TrustedDeviceHelper.
  TRUST_DURATION = 90.days

  has_many :contacts, foreign_key: :synkra_global_user_id, inverse_of: :synkra_global_user, dependent: nil

  validates :email, presence: true, uniqueness: { case_sensitive: false }

  before_validation { self.email = email&.downcase&.strip }

  def self.find_or_initialize_by_email(email)
    find_or_initialize_by(email: email.to_s.downcase.strip)
  end

  def email_verified?
    email_verified_at.present?
  end

  def otp_resend_allowed?
    otp_sent_at.blank? || otp_sent_at < OTP_RESEND_COOLDOWN.ago
  end

  # Generates a fresh OTP, stores only its digest, and emails it. Resets
  # the attempt counter so a new code always gets a full set of tries.
  # Returns false (without sending anything) if called again too soon.
  def generate_and_send_otp!
    return false unless otp_resend_allowed?

    code = SecureRandom.random_number(10**OTP_LENGTH).to_s.rjust(OTP_LENGTH, '0')

    update!(
      otp_digest: self.class.digest_otp(code),
      otp_sent_at: Time.current,
      otp_expires_at: OTP_VALID_FOR.from_now,
      otp_attempts: 0
    )

    SynkraIdentityMailer.otp_code(global_user: self, code: code).deliver_later
    true
  end

  # Returns true/false. Never raises on a wrong code - just counts the
  # attempt. Callers should treat a false return as "show an error", not
  # as an exceptional condition.
  def verify_otp(code)
    return false if otp_digest.blank?
    return false if otp_expires_at.blank? || otp_expires_at < Time.current
    return false if otp_attempts >= MAX_OTP_ATTEMPTS

    if ActiveSupport::SecurityUtils.secure_compare(otp_digest, self.class.digest_otp(code.to_s))
      update!(
        email_verified_at: email_verified_at || Time.current,
        otp_digest: nil,
        otp_sent_at: nil,
        otp_expires_at: nil,
        otp_attempts: 0
      )
      true
    else
      increment!(:otp_attempts)
      false
    end
  end

  # A long-lived, purpose-scoped signed token identifying this global
  # user - this is what a "trusted device" cookie actually stores. Only
  # ever generated AFTER a successful OTP verification.
  def generate_trust_token
    signed_id(purpose: :trusted_device, expires_in: TRUST_DURATION)
  end

  def self.find_by_trust_token(token)
    return nil if token.blank?

    find_signed(token, purpose: :trusted_device)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def self.digest_otp(code)
    Digest::SHA256.hexdigest("#{code}:#{Rails.application.secret_key_base}")
  end
end
