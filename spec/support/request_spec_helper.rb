module RequestSpecHelper
  def json
    JSON.parse(response.body)
  end

  # Extracts JSON:API attributes from { data: { attributes: ... } } responses.
  def jsonapi_attributes(response_body = response.body)
    ActiveSupport::JSON.decode(response_body).fetch("data").fetch("attributes")
  end

  def jsonapi_collection_attributes(response_body = response.body)
    ActiveSupport::JSON.decode(response_body).fetch("data").map { |item| item.fetch("attributes") }
  end

  def bearer_auth_headers(user, extra: {})
    { "Authorization" => "Bearer #{JwtService.encode(user)}" }.merge(extra)
  end

  # For request specs, prefer signing in via the real endpoint so the cookie
  # jar matches how Rails sets signed cookies.
  def sign_in_as(user, password: "password")
    post session_path, params: { email_address: user.email_address, password: password }
    user.sessions.order(:created_at).last
  end
end

