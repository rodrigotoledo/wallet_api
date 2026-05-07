class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
    head :ok
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      if request.format.json?
        render json: {
          token: JwtService.encode(user),
          token_type: "Bearer",
          expires_in: JwtService::EXPIRATION.to_i,
          user: user_json(user),
          tenant: tenant_json(user.tenant)
        }, status: :created
      else
        start_new_session_for user
        redirect_to after_authentication_url
      end
    else
      if request.format.json?
        render json: {
          error: "invalid_credentials",
          message: "Try another email address or password."
        }, status: :unauthorized
      else
        redirect_to new_session_path, alert: "Try another email address or password."
      end
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private

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
