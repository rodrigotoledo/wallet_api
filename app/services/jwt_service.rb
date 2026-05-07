class JwtService
  ALGORITHM = "HS256"
  EXPIRATION = 24.hours

  class << self
    def encode(user)
      payload = {
        user_id: user.id,
        tenant_id: user.tenant_id,
        exp: EXPIRATION.from_now.to_i
      }

      JWT.encode(payload, secret_key, ALGORITHM)
    end

    def decode(token)
      JWT.decode(token, secret_key, true, algorithm: ALGORITHM).first
    end

    private

    def secret_key
      Rails.application.secret_key_base
    end
  end
end
