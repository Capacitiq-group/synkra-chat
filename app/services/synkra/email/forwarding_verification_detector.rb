module Synkra
  module Email
    # Detects forwarding-verification emails sent by mailbox providers
    # (Google, Microsoft, Yahoo, etc.) when a customer sets up forwarding
    # to a Synkra ingress address. On match, the caller marks the
    # Channel::Email with forwarding_verification_pending_at, which the
    # inbox Configuration page and super admin review view read from.
    #
    # Match heuristics: sender address AND subject keyword. Both must
    # match. This is deliberately conservative - false positives mean the
    # inbox gets flagged for a normal customer email, which is worse than
    # a false negative the customer can notice themselves (they'll see
    # the verification email in their conversation list and click the
    # link manually).
    class ForwardingVerificationDetector
      RULES = [
        {
          provider: 'google',
          sender_domains: %w[google.com],
          sender_local_parts: %w[forwarding-noreply],
          subject_pattern: /forwarding\s+confirmation|confirmation\s+to\s+forward/i
        },
        {
          provider: 'microsoft',
          sender_domains: %w[microsoft.com office365.com outlook.com],
          sender_local_parts: %w[no-reply noreply],
          subject_pattern: /forwarding|verify\s+your\s+forwarding|confirm\s+forwarding/i
        }
      ].freeze

      def initialize(mail)
        @mail = mail
      end

      # Returns the provider symbol ('google', 'microsoft') on match,
      # or nil if not a verification email. Callers typically do
      #   provider = Detector.new(mail).detect
      #   channel.update!(forwarding_verification_pending_at: Time.current) if provider
      def detect
        rule = RULES.find { |r| matches?(r) }
        rule && rule[:provider]
      end

      private

      attr_reader :mail

      def matches?(rule)
        from = extract_from
        return false if from.blank?

        local, domain = split_address(from)
        return false if domain.blank? || local.blank?

        return false unless rule[:sender_domains].any? { |d| domain == d || domain.end_with?(".#{d}") }
        return false unless rule[:sender_local_parts].include?(local.downcase)

        subject = mail.subject.to_s
        return false if subject.blank?

        rule[:subject_pattern].match?(subject)
      end

      def extract_from
        addr = mail.from
        addr = addr.first if addr.respond_to?(:first)
        addr = addr.to_s if addr
        addr
      rescue StandardError
        nil
      end

      def split_address(email)
        local, domain = email.to_s.downcase.split('@', 2)
        [local, domain]
      end
    end
  end
end
