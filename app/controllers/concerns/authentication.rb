module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    before_action :set_tenant
    helper_method :authenticated?, :current_user, :current_tenant
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session || resume_jwt
    end

    def require_authentication
      authenticated? || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def resume_jwt
      Current.user ||= find_user_from_jwt if jwt_token.present?
    end

    def set_tenant
      Current.tenant = current_user.tenant if current_user
    end

    def current_user
      Current.session&.user || Current.user
    end

    def current_tenant
      Current.tenant
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def jwt_token
      request.headers['Authorization']&.split(' ')&.last
    end

    def find_user_from_jwt
      return unless jwt_token.present?

      payload = JwtService.decode(jwt_token)
      User.find(payload["user_id"])
    rescue => e
      Rails.logger.warn "[Auth] JWT decode failed: #{e.message}"
      nil
    end

    def request_authentication
      if request.format.json?
        render json: { error: "unauthorized", message: "Authentication required" }, status: :unauthorized
      else
        session[:return_to_after_authenticating] = request.url
        redirect_to new_session_path
      end
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
