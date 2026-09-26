# Community Access Programme (60% off): an application reviewed by a
# person, not automatic eligibility. Registration alone doesn't qualify
# - the community initiative itself is what gets verified - and
# faith-based organisations must show a genuine, ongoing initiative
# with tangible non-religious community benefit. Answers are stored on
# SynkraProgrammeVerification#application_data; evidence files on
# #documents.
#
# Two entry points: an existing account applying from inside the app
# (account/user present), and the public form at /community-access with
# no login (account/user nil, contact_email required instead) - see
# submit_public. Both funnel through the same validation and review
# queue so nothing diverges between them.
class Billing::CommunityApplicationService
  PROGRAMME = 'community'.freeze
  MAX_APPLICATIONS_PER_DAY = 3

  Result = Struct.new(:success?, :code, :data, keyword_init: true)

  # key => required? (registration_number is conditionally required below)
  TEXT_FIELDS = %w[
    organisation_name organisation_type registration_status registration_number country address
    website social_url general_email general_phone
    contact_name contact_role contact_email contact_phone account_person billing_contact
    organisation_description initiative_description initiative_serves initiative_location initiative_frequency
    faith_initiative_benefit evidence_links
  ].freeze

  REQUIRED_FIELDS = %w[
    organisation_name organisation_type registration_status country address
    contact_name contact_role contact_email contact_phone
    organisation_description initiative_description initiative_serves initiative_location initiative_frequency
  ].freeze

  def initialize(account: nil, user: nil)
    @account = account
    @user = user
  end

  # Public form, no Synkra account yet. contact_email is where the
  # confirmation, status link and eventual decision go - it isn't
  # validated as a Synkra login, just an inbox someone reads.
  def submit_public(fields:, files:, contact_email:)
    contact_email = contact_email.to_s.strip
    return failure(:invalid_email) unless contact_email.match?(URI::MailTo::EMAIL_REGEXP)

    result = submit(fields: fields, files: files, contact_email: contact_email)
    return result unless result.success?

    Billing::ProgrammeMailer.application_received(verification: result.data[:verification]).deliver_later
    result
  end

  # Attaches an approved public application to a real account - the
  # applicant enters their reference code (SynkraProgrammeVerification#
  # access_token) once they've created or logged into a Synkra account.
  def self.claim(access_token:, account:, user:)
    verification = SynkraProgrammeVerification.claimable(access_token.to_s.strip.upcase)
    return Result.new(success?: false, code: :invalid_code) if verification.nil?
    # Ties the code to whoever actually applied - otherwise anyone who
    # gets hold of a valid, still-unclaimed code (forwarded, guessed,
    # intercepted) could claim someone else's approved discount onto
    # their own account, first-come-first-served.
    return Result.new(success?: false, code: :email_mismatch) unless verification.contact_email.to_s.strip.casecmp?(user.email.to_s.strip)
    return Result.new(success?: false, code: :already_has_programme) if SynkraProgrammeVerification.active_verification_for(account.id, PROGRAMME)

    verification.claim!(account: account, user: user)
    Result.new(success?: true, data: { verification: verification })
  end

  def submit(fields:, files:, contact_email: nil)
    data = clean(fields)
    files = usable_files(files)

    missing = missing_fields(data)
    return failure(:missing_fields, fields: missing) if missing.any?
    return failure(:declaration_required) unless data['no_ai_images'] == true
    return failure(:evidence_required) if files.empty? && data['evidence_links'].blank?
    return failure(:faith_photo_required) if data['faith_based'] && files.none? { |f| f.content_type.start_with?('image/') }

    file_error = file_failure(files)
    return file_error if file_error

    duplicate_error = duplicate_or_rate_limit_failure(contact_email)
    return duplicate_error if duplicate_error

    verification = create_application(data, files, contact_email)
    Billing::ProgrammeMailer.review_requested(verification: verification).deliver_later
    Result.new(success?: true, data: { verification: verification })
  end

  # The reviewer asked for more information: attach the extra
  # evidence/answer and put the application back in the review queue.
  # Either pass access_token (public applicant) or leave it nil to use
  # the initializer's account (in-app applicant).
  def add_information(message:, files:, access_token: nil)
    verification = if access_token.present?
                     SynkraProgrammeVerification.for_programme(PROGRAMME)
                                                .where(access_token: access_token.to_s.strip.upcase, status: 'needs_info').first
                   else
                     SynkraProgrammeVerification.for_programme(PROGRAMME)
                                                .where(account_id: @account.id, status: 'needs_info').order(created_at: :desc).first
                   end
    return failure(:nothing_to_update) if verification.nil?

    files = usable_files(files)
    return failure(:evidence_required) if files.empty? && message.to_s.strip.blank?

    file_error = file_failure(files)
    return file_error if file_error

    verification.documents.attach(files) if files.any?
    extra = verification.application_data.to_h.merge(
      'additional_information' => [verification.application_data['additional_information'], message.to_s.strip].compact_blank.join("\n\n")
    )
    verification.update!(status: 'review', application_data: extra, submitted_at: Time.current)
    Billing::ProgrammeMailer.review_requested(verification: verification).deliver_later
    Result.new(success?: true, data: { verification: verification })
  end

  private

  def duplicate_or_rate_limit_failure(contact_email)
    if @account
      return failure(:already_verified) if SynkraProgrammeVerification.active_verification_for(@account.id, PROGRAMME)
      return failure(:already_submitted) if SynkraProgrammeVerification.for_programme(PROGRAMME).where(account_id: @account.id, status: 'review').exists?
    elsif SynkraProgrammeVerification.for_programme(PROGRAMME).where(contact_email: contact_email, status: %w[review needs_info verified]).exists?
      return failure(:already_submitted)
    end

    failure(:rate_limited) if recent_applications(contact_email) >= MAX_APPLICATIONS_PER_DAY
  end

  def failure(code, data = {})
    Result.new(success?: false, code: code, data: data)
  end

  def clean(fields)
    fields = fields.respond_to?(:to_unsafe_h) ? fields.to_unsafe_h : fields.to_h
    fields = fields.stringify_keys
    data = TEXT_FIELDS.index_with { |key| fields[key].to_s.strip.first(2000) }.compact_blank
    data['faith_based'] = ActiveModel::Type::Boolean.new.cast(fields['faith_based']) == true
    data['no_ai_images'] = ActiveModel::Type::Boolean.new.cast(fields['no_ai_images']) == true
    data
  end

  def missing_fields(data)
    missing = REQUIRED_FIELDS.select { |key| data[key].blank? }
    missing << 'registration_number' if data['registration_status'] == 'registered' && data['registration_number'].blank?
    missing << 'faith_initiative_benefit' if data['faith_based'] && data['faith_initiative_benefit'].blank?
    missing
  end

  def usable_files(files)
    Array(files).select { |file| file.respond_to?(:content_type) && file.respond_to?(:size) }
  end

  def file_failure(files)
    return failure(:too_many_files) if files.size > SynkraProgrammeVerification::DOCUMENT_MAX_COUNT
    return failure(:invalid_file_type) unless files.all? { |f| SynkraProgrammeVerification::DOCUMENT_CONTENT_TYPES.include?(f.content_type) }
    return failure(:file_too_large) if files.any? { |f| f.size > SynkraProgrammeVerification::DOCUMENT_MAX_SIZE }

    nil
  end

  def recent_applications(contact_email)
    scope = SynkraProgrammeVerification.for_programme(PROGRAMME).where('created_at > ?', 24.hours.ago)
    scope = @account ? scope.where(account_id: @account.id) : scope.where(contact_email: contact_email)
    scope.count
  end

  def create_application(data, files, contact_email)
    SynkraProgrammeVerification.transaction do
      if @account
        SynkraProgrammeVerification.for_programme(PROGRAMME)
                                   .where(account_id: @account.id, status: %w[needs_info pending])
                                   .update_all(status: 'superseded', updated_at: Time.current)
      end
      record = SynkraProgrammeVerification.create!(
        account_id: @account&.id, user_id: @user&.id, programme: PROGRAMME, verification_method: 'application',
        status: 'review', application_data: data, submitted_at: Time.current,
        contact_email: contact_email, access_token: (SynkraProgrammeVerification.generate_access_token unless @account)
      )
      record.documents.attach(files) if files.any?
      record
    end
  end
end
