require "test_helper"

class Api::V1::TransactionsControllerTest < ActionDispatch::IntegrationTest
  test "returns authenticated user transactions ordered by newest first" do
    tenant = Tenant.create!(name: "Tenant", subdomain: "tx-tenant-#{SecureRandom.hex(4)}")
    user = User.create!(tenant: tenant, email_address: "tx-user@example.com", password: "password123")
    account = Account.create!(tenant: tenant, user: user, balance: 100.00)

    older = Transaction.create!(
      tenant: tenant,
      user: user,
      account: account,
      type: "Deposit",
      amount: 10.00,
      currency: "USD",
      status: :completed,
      created_at: 1.hour.ago
    )
    newer = Transaction.create!(
      tenant: tenant,
      user: user,
      account: account,
      type: "Withdrawal",
      amount: 5.00,
      currency: "USD",
      status: :completed
    )

    get api_v1_transactions_path,
      headers: { "Authorization" => "Bearer #{JwtService.encode(user)}" },
      as: :json

    assert_response :success

    body = jsonapi_collection
    assert_equal [ newer.id, older.id ], body.map { |transaction| transaction["id"] }
    assert_equal [ "Withdrawal", "Deposit" ], body.map { |transaction| transaction["type"] }
  end
end
