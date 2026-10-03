class Api::V1::Accounts::Billing::AiOpsAddonsController < Api::V1::Accounts::BaseController
  before_action -> { check_authorization(SynkraSubscription) }

  def index
    render json: { packs: Billing::AiOpsAddonPack::PACKS }
  end

  def create
    pack = Billing::AiOpsAddonPack.find(params[:pack_key])
    if pack.blank?
      render json: { error: 'Invalid pack' }, status: :unprocessable_entity
      return
    end

    result = Billing::PaystackService.new.initialize_transaction(
      email: Current.user.email,
      amount_zar: pack[:price_zar],
      callback_url: params[:callback_url].presence || "#{root_url}app/accounts/#{Current.account.id}/settings/billing",
      metadata: {
        synkra_account_id: Current.account.id,
        purchase_type: 'ai_ops_addon',
        pack_key: pack[:key]
      }
    )

    unless result.success?
      render json: { error: result.error }, status: :unprocessable_entity
      return
    end

    AiOpsAddonPurchase.create!(
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
