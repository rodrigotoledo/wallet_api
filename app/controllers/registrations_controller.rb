class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: :create

  def create
    result = RegistrationService.call(**registration_params.to_h.symbolize_keys)

    if result.success?
      user = result.user
      render json: {
        token: JwtService.encode(user),
        token_type: "Bearer",
        expires_in: JwtService::EXPIRATION.to_i,
        user: user_json(user),
        tenant: tenant_json(user.tenant)
      }, status: :created
    else
      render json: {
        error: "registration_failed",
        message: result.message,
        errors: result.errors
      }, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:registration).permit(:email_address, :password, :password_confirmation, :tenant_name)
  end

  def user_json(user)
    account = user.account

    {
      id: user.id,
      email_address: user.email_address,
      tenant_id: user.tenant_id,
      balance: account&.balance.to_f,
      currency: account&.currency || "USD"
    }
  end

  def tenant_json(tenant)
    {
      id: tenant.id,
      name: tenant.name,
      subdomain: tenant.subdomain
    }
  end
end
