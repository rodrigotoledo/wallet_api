require "test_helper"

class Api::V1::ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "returns current user balance and tenant" do
    tenant = Tenant.create!(name: "Tenant", subdomain: "profile-#{SecureRandom.hex(4)}")
    user = User.create!(tenant: tenant, email_address: "profile@example.com", password: "password123")
    Account.create!(tenant: tenant, user: user, balance: 42.50)

    get api_v1_profile_path,
      headers: { "Authorization" => "Bearer #{JwtService.encode(user)}" },
      as: :json

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal user.id, body["user"]["id"]
    assert_equal 42.50, body["user"]["balance"].to_f
    assert_equal "USD", body["user"]["currency"]
    assert_equal tenant.id, body["tenant"]["id"]
  end
end
