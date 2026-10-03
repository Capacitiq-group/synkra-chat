# Message add-on packs - see Billing::MessageAddonPack for the
# catalogue and MessageAddonPurchase for the ledger. Admin-only,
# same as the rest of billing (SynkraSubscriptionPolicy).
class Api::V1::Accounts::Billing::MessageAddonsController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(SynkraSubscription) }

  def index
    render json: { packs: Billing::MessageAddonPack::PACKS }
  end

  # Starts a one-time Paystack checkout for a pack. The credit itself
  # is only granted once Billing::PaystackWebhookHandler sees the
  # matching charge.success event - see that class's
  # handle_message_addon_purchase. Returns the authorization_url the
  # frontend should redirect the browser to, same shape as
  # SubscriptionsController#checkout.
  def create
    pack = Billing::MessageAddonPack.find(params[:pack_key])
    if pack.blank?
      render json: { error: 'Invalid pack' }, status: :unprocessable_entity
      return
    end

    result = Billing::PaystackService.new.initialize_transaction(
      email: Current.user.email,
      amount_zar: pack[:price_zar],
      callback_url: params[:callback_url].presence || "#{root_url}app/accounts/#{Current.account.id}/settings/billing",
      metadata: { synkra_account_id: Current.account.id, purchase_type: 'message_addon', pack_key: pack[:key] }
    )

    unless result.success?
      render json: { error: result.error }, status: :unprocessable_entity
      return
    end

    # Recorded as pending BEFORE redirecting the customer - the webhook
    # only has a reference to work with, so the row needs to already
    # exist for it to find and complete. If the customer never
    # completes checkout, this row just stays pending forever - no
    # cleanup needed, it never granted credit.
    MessageAddonPurchase.create!(
      account_id: Current.account.id,
      pack_key: pack[:key],
      units: pack[:units],
      price_zar: pack[:price_zar],
      paystack_reference: result.data['reference'],
      status: 'pending'
    )

    render json: { authorization_url: result.data['authorization_url'] }
  end
end
