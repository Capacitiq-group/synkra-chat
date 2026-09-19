# Handles a Chat account user clicking "unsubscribe" from a
# MarketingMailer email - a plain browser navigation, not an API call.
# Token-based, no login required (matching
# ContactEmailVerificationsController's pattern) - someone must be
# able to unsubscribe without needing to remember their password.
class MarketingUnsubscriptionsController < ActionController::Base
  layout false

  def show
    user = User.find_signed(params[:token], purpose: :unsubscribe_marketing)

    if user.nil?
      @status = :invalid
    else
      user.update!(marketing_emails_opt_in: false)
      @status = :unsubscribed
    end
  end
end
