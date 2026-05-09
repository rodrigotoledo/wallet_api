require "rails_helper"

RSpec.describe "API::V1::Transactions", type: :request do
  it "returns authenticated user transactions ordered by newest first" do
    tenant = create(:tenant)
    user = create(:user, tenant:)
    account = create(:account, tenant:, user:, balance: 100.00, currency: "USD")

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
      headers: bearer_auth_headers(user),
      as: :json

    expect(response).to have_http_status(:ok)

    body = jsonapi_collection_attributes
    expect(body.map { |tx| tx["id"] }).to eq([ newer.id, older.id ])
    expect(body.map { |tx| tx["type"] }).to eq([ "Withdrawal", "Deposit" ])
  end
end

