# Public Community Access application - no Synkra account required.
# Same review queue and rules as the in-app version
# (Billing::CommunityApplicationService), just reachable without
# logging in first. A plain browser page/form, not an API call -
# matches ContactEmailVerificationsController/
# MarketingUnsubscriptionsController's pattern.
class CommunityAccessController < ActionController::Base
  layout false

  ORGANISATION_TYPES = %w[NPO NGO NPC CHARITY CBO FAITH OTHER].freeze
  REGISTRATION_STATUSES = %w[registered in_progress not_registered].freeze

  def new
    @programme_prices = SynkraPlan.programme_prices('community')
  end

  def create
    result = Billing::CommunityApplicationService.new.submit_public(
      fields: params, files: Array(params[:documents]), contact_email: params[:applicant_email]
    )

    if result.success?
      redirect_to status_community_access_path(result.data[:verification].access_token)
    else
      @error = result.code
      @programme_prices = SynkraPlan.programme_prices('community')
      @submitted_fields = params
      render :new, status: :unprocessable_entity
    end
  end

  def status
    @verification = SynkraProgrammeVerification.find_by(access_token: params[:token].to_s.strip.upcase, programme: 'community')
    head :not_found and return if @verification.nil?
  end

  def add_information
    @verification = SynkraProgrammeVerification.find_by(access_token: params[:token].to_s.strip.upcase, programme: 'community')
    if @verification.nil?
      head :not_found
      return
    end

    result = Billing::CommunityApplicationService.new.add_information(
      message: params[:message], files: Array(params[:documents]), access_token: @verification.access_token
    )
    @error = result.code unless result.success?
    render :status
  end
end
