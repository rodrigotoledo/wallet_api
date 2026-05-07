require "test_helper"

class Api::V1::DepositsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Setup first tenant and user
    @tenant1 = Tenant.create!(name: "Tenant 1", subdomain: "tenant-1-#{rand(10000)}")
    @user1 = User.create!(
      tenant: @tenant1,
      email_address: "user1-#{rand(10000)}@example.com",
      password: "password123"
    )
    @account1 = Account.create!(tenant: @tenant1, user: @user1, balance: 100.00)

    # Setup second tenant and user
    @tenant2 = Tenant.create!(name: "Tenant 2", subdomain: "tenant-2-#{rand(10000)}")
    @user2 = User.create!(
      tenant: @tenant2,
      email_address: "user2-#{rand(10000)}@example.com",
      password: "password123"
    )
    @account2 = Account.create!(tenant: @tenant2, user: @user2, balance: 50.00)
  end

  test "creates deposit with bearer token" do
    user = users(:one)
    token = JwtService.encode(user)

    assert_difference -> { Deposit.count }, 1 do
      post api_v1_deposits_path,
        params: {
          deposit: {
            amount: "12.50",
            currency: "USD",
            reference: "jwt-deposit-test"
          }
        },
        headers: {
          "Authorization" => "Bearer #{token}",
          "Idempotency-Key" => "jwt-deposit-test-#{SecureRandom.uuid}"
        },
        as: :json
    end

    assert_response :created
    assert_equal "completed", JSON.parse(response.body)["data"]["attributes"]["status"]
  end

  test "authenticated user can deposit to their account" do
    token = JwtService.encode(@user1)

    post api_v1_deposits_path,
      params: {
        deposit: { amount: 25.00 }
      },
      headers: { "Authorization" => "Bearer #{token}", "Idempotency-Key" => SecureRandom.uuid },
      as: :json

    assert_response :created

    body = JSON.parse(response.body)["data"]["attributes"]
    assert body["id"].present?
    assert_equal 25.00, body["amount"].to_f
    assert_equal 125.00, body["balance"].to_f

    # Verify balance was updated
    assert_equal 125.00, @account1.reload.balance
  end

  test "deposit is isolated by tenant" do
    token1 = JwtService.encode(@user1)

    # User1 deposits
    post api_v1_deposits_path,
      params: {
        deposit: { amount: 50.00 }
      },
      headers: { "Authorization" => "Bearer #{token1}", "Idempotency-Key" => SecureRandom.uuid },
      as: :json

    assert_response :created

    # User1's account should be updated
    assert_equal 150.00, @account1.reload.balance

    # User2's account should NOT be affected
    assert_equal 50.00, @account2.reload.balance
  end

  test "deposit with idempotency key is idempotent" do
    token = JwtService.encode(@user1)
    idempotency_key = "unique-key-#{SecureRandom.hex}"

    # First deposit
    post api_v1_deposits_path,
      params: {
        deposit: { amount: 25.00 }
      },
      headers: {
        "Authorization" => "Bearer #{token}",
        "Idempotency-Key" => idempotency_key
      },
      as: :json

    assert_response :created
    body1 = JSON.parse(response.body)["data"]["attributes"]
    first_balance = @account1.reload.balance

    # Retry same request
    post api_v1_deposits_path,
      params: {
        deposit: { amount: 25.00 }
      },
      headers: {
        "Authorization" => "Bearer #{token}",
        "Idempotency-Key" => idempotency_key
      },
      as: :json

    assert_response :created
    body2 = JSON.parse(response.body)["data"]["attributes"]

    # Should return same result
    assert_equal body1["id"], body2["id"]
    assert_equal first_balance, @account1.reload.balance
  end

  test "transaction belongs to correct tenant" do
    token = JwtService.encode(@user1)

    post api_v1_deposits_path,
      params: {
        deposit: { amount: 40.00 }
      },
      headers: { "Authorization" => "Bearer #{token}", "Idempotency-Key" => SecureRandom.uuid },
      as: :json

    assert_response :created

    transaction = Transaction.where(account_id: @account1.id).last
    assert_equal @tenant1.id, transaction.tenant_id
    assert_not_equal @tenant2.id, transaction.tenant_id
  end
end
