# Synkra Chat billing: account-facing billing management. Admin-only,
# enforced by SynkraSubscriptionPolicy - agents should never see or
# touch billing.
#
# check_authorization's default (controller_name.classify.constantize)
# would resolve this controller's name to a bare `Subscription`
# constant, which doesn't exist - our model is namespaced as
# SynkraSubscription - so the model has to be passed explicitly.
class Api::V1::Accounts::Billing::SubscriptionsController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(SynkraSubscription) }
  before_action :fetch_subscription

  def show
    render json: subscription_payload
  end

  # Starts a Paystack checkout for the given plan. Returns the
  # authorization_url the frontend should redirect the browser to.
  def checkout
    plan = params[:plan].to_s
    unless SynkraPlan.valid?(plan)
      render json: { error: 'Invalid plan' }, status: :unprocessable_entity
      return
    end

    plan_config = SynkraPlan.find(plan)
    if plan_config[:paystack_plan_code].blank?
      render json: { error: 'This plan is not yet available for checkout' }, status: :unprocessable_entity
      return
    end

    result = Billing::PaystackService.new.initialize_transaction(
      email: Current.user.email,
      amount_zar: plan_config[:price_zar],
      plan_code: plan_config[:paystack_plan_code],
      callback_url: params[:callback_url].presence || "#{root_url}app/accounts/#{Current.account.id}/settings/billing",
      metadata: { synkra_account_id: Current.account.id, plan: plan }
    )

    if result.success?
      render json: { authorization_url: result.data['authorization_url'] }
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  # Schedules a downgrade/switch to a different plan, or an upgrade
  # applied immediately - change_plan! already knows the difference.
  def change_plan
    plan = params[:plan].to_s
    unless SynkraPlan.valid?(plan)
      render json: { error: 'Invalid plan' }, status: :unprocessable_entity
      return
    end

    @subscription.change_plan!(plan)
    render json: subscription_payload
  end

  def cancel
    @subscription.schedule_cancellation!
    render json: subscription_payload
  end

  def resume
    @subscription.update!(cancel_at_period_end: false)
    render json: subscription_payload
  end

  private

  def fetch_subscription
    @subscription = Current.account.synkra_subscription
  end

  def subscription_payload
    {
      plan: @subscription.plan,
      plan_name: @subscription.plan_config[:name],
      price_zar: @subscription.plan_config[:price_zar],
      status: @subscription.status,
      billing_cycle: @subscription.billing_cycle,
      current_period_start: @subscription.current_period_start,
      current_period_end: @subscription.current_period_end,
      cancel_at_period_end: @subscription.cancel_at_period_end,
      pending_plan: @subscription.pending_plan,
      usage: {
        business_initiated_messages_used: @subscription.business_initiated_messages_used,
        business_initiated_message_allowance: @subscription.business_initiated_message_allowance,
        usage_fraction: @subscription.usage_fraction,
        purchased_message_credits: @subscription.purchased_message_credits,
        seats_used: Current.account.account_users.count,
        effective_seat_limit: @subscription.effective_seat_limit,
        purchased_extra_seats: @subscription.purchased_extra_seats,
        # storage_used_mb is cached, up to ~24h stale - see
        # Billing::RecalculateStorageUsageJob.
        storage_used_mb: @subscription.storage_used_mb,
        storage_mb_allowance: @subscription.plan_config[:storage_mb_allowance],
        storage_overage_gb: @subscription.storage_overage_gb,
        # Temporary Chat-local tracking while Flow (and Automations)
        # is hidden - see synkra_plan.rb's header comment.
        ai_ops_used: @subscription.ai_ops_used,
        ai_ops_allowance: @subscription.ai_ops_allowance,
        emails_used: @subscription.emails_used,
        email_allowance: @subscription.email_allowance
      }
    }
  end
end
