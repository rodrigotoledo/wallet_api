require "test_helper"

class Api::V1::TenantUsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = tenants(:demo)
    @alice = users(:alice)
    @bob = users(:bob)
    @charlie = users(:charlie)
  end

  test "returns users from the same tenant excluding current user" do
    get api_v1_tenant_users_path,
      headers: { "Authorization" => "Bearer #{JwtService.encode(@alice)}" },
      as: :json

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal 2, body.length # Bob and Charlie, excluding Alice

    user_ids = body.map { |user| user["id"] }
    assert_includes user_ids, @bob.id
    assert_includes user_ids, @charlie.id
    assert_not_includes user_ids, @alice.id

    # Check structure
    bob_data = body.find { |user| user["id"] == @bob.id }
    assert_equal @bob.email_address, bob_data["email_address"]
    assert_equal @bob.email_address, bob_data["name"] # Using email as name for now
    assert_equal 500.0, bob_data["balance"]
  end

  test "isolates users by tenant" do
    # Create a user in a different tenant
    other_tenant = Tenant.create!(name: "Other Tenant", subdomain: "other")
    other_user = User.create!(
      email_address: "other@example.com",
      password_digest: BCrypt::Password.create("password"),
      tenant: other_tenant
    )
    Account.create!(tenant: other_tenant, user: other_user, currency: "USD", balance: 100)

    get api_v1_tenant_users_path,
      headers: { "Authorization" => "Bearer #{JwtService.encode(@alice)}" },
      as: :json

    assert_response :success

    body = JSON.parse(response.body)
    user_ids = body.map { |user| user["id"] }

    # Should not include the user from other tenant
    assert_not_includes user_ids, other_user.id
  end
end