require "rails_helper"

RSpec.describe "API::V1::Deposits", type: :request do
  let!(:tenant1) { create(:tenant) }
  let!(:user1) { create(:user, tenant: tenant1) }
  let!(:account1) { create(:account, tenant: tenant1, user: user1, balance: 100.00, currency: "USD") }

  let!(:tenant2) { create(:tenant) }
  let!(:user2) { create(:user, tenant: tenant2) }
  let!(:account2) { create(:account, tenant: tenant2, user: user2, balance: 50.00, currency: "USD") }

  it "creates deposit with bearer token" do
    token = JwtService.encode(user1)

    expect do
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
    end.to change(Deposit, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(jsonapi_attributes["status"]).to eq("completed")
  end

  it "allows an authenticated user to deposit to their account" do
    post api_v1_deposits_path,
      params: { deposit: { amount: 25.00 } },
      headers: bearer_auth_headers(user1, extra: { "Idempotency-Key" => SecureRandom.uuid }),
      as: :json

    expect(response).to have_http_status(:created)

    body = jsonapi_attributes
    expect(body["id"]).to be_present
    expect(body["amount"].to_f).to eq(25.00)
    expect(body["balance"].to_f).to eq(125.00)
    expect(account1.reload.balance.to_f).to eq(125.00)
  end

  it "isolates deposits by tenant" do
    post api_v1_deposits_path,
      params: { deposit: { amount: 50.00 } },
      headers: bearer_auth_headers(user1, extra: { "Idempotency-Key" => SecureRandom.uuid }),
      as: :json

    expect(response).to have_http_status(:created)
    expect(account1.reload.balance.to_f).to eq(150.00)
    expect(account2.reload.balance.to_f).to eq(50.00)
  end

  it "is idempotent with the same idempotency key" do
    idempotency_key = "unique-key-#{SecureRandom.hex}"

    post api_v1_deposits_path,
      params: { deposit: { amount: 25.00 } },
      headers: bearer_auth_headers(user1, extra: { "Idempotency-Key" => idempotency_key }),
      as: :json

    expect(response).to have_http_status(:created)
    body1 = jsonapi_attributes
    first_balance = account1.reload.balance

    post api_v1_deposits_path,
      params: { deposit: { amount: 25.00 } },
      headers: bearer_auth_headers(user1, extra: { "Idempotency-Key" => idempotency_key }),
      as: :json

    expect(response).to have_http_status(:created)
    body2 = jsonapi_attributes

    expect(body2["id"]).to eq(body1["id"])
    expect(account1.reload.balance).to eq(first_balance)
  end

  it "creates a transaction belonging to the correct tenant" do
    post api_v1_deposits_path,
      params: { deposit: { amount: 40.00 } },
      headers: bearer_auth_headers(user1, extra: { "Idempotency-Key" => SecureRandom.uuid }),
      as: :json

    expect(response).to have_http_status(:created)

    transaction = Transaction.where(account_id: account1.id).last
    expect(transaction.tenant_id).to eq(tenant1.id)
    expect(transaction.tenant_id).not_to eq(tenant2.id)
  end
end

