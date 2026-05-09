require "rails_helper"

RSpec.describe "API::V1::Transfers", type: :request do
  let!(:tenant) { create(:tenant) }
  let!(:alice) { create(:user, tenant:, email_address: "alice@example.com") }
  let!(:bob) { create(:user, tenant:, email_address: "bob@example.com") }
  let!(:alice_account) { create(:account, tenant:, user: alice, balance: 100.00, currency: "USD") }
  let!(:bob_account) { create(:account, tenant:, user: bob, balance: 500.00, currency: "USD") }

  it "creates a transfer between users and completes after processing job" do
    initial_alice_balance = alice_account.balance
    initial_bob_balance = bob_account.balance

    post api_v1_transfers_path,
      headers: bearer_auth_headers(alice),
      params: {
        transfer: {
          recipient_id: bob.id,
          amount: 50,
          currency: "USD"
        }
      },
      as: :json

    expect(response).to have_http_status(:created)

    body = jsonapi_attributes
    expect(body["type"]).to eq("Transfer")
    expect(body["amount"].to_f).to eq(50.0)
    expect(body["status"]).to eq("pending")
    expect(body["balance"].to_f).to eq(initial_alice_balance.to_f)

    expect(body.dig("recipient", "id")).to eq(bob.id)
    expect(body.dig("recipient", "email")).to eq(bob.email_address)

    alice_tx = Transaction.find_by(account: alice_account, type: "Transfer")
    bob_tx = Transaction.find_by(account: bob_account, type: "Deposit")

    expect(alice_tx).to be_present
    expect(bob_tx).to be_present
    expect(alice_tx.status).to eq("pending")
    expect(bob_tx.status).to eq("pending")
    expect(alice_tx.recipient_user).to eq(bob)

    TransferProcessorJob.new.perform(alice_tx.id)

    alice_account.reload
    bob_account.reload
    alice_tx.reload
    bob_tx.reload

    expect(alice_account.balance).to eq(initial_alice_balance - 50)
    expect(bob_account.balance).to eq(initial_bob_balance + 50)
    expect(alice_tx.status).to eq("completed")
    expect(bob_tx.status).to eq("completed")
  end

  it "fails with insufficient funds" do
    post api_v1_transfers_path,
      headers: bearer_auth_headers(alice),
      params: {
        transfer: {
          recipient_id: bob.id,
          amount: 2000,
          currency: "USD"
        }
      },
      as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["error"]).to eq("unprocessable_entity")
    expect(json["details"]).to include("insufficient_funds")
  end

  it "fails when transferring to self" do
    post api_v1_transfers_path,
      headers: bearer_auth_headers(alice),
      params: {
        transfer: {
          recipient_id: alice.id,
          amount: 50,
          currency: "USD"
        }
      },
      as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["error"]).to eq("unprocessable_entity")
    expect(json["details"]).to include("sender and recipient must be different")
  end

  it "fails with invalid recipient" do
    post api_v1_transfers_path,
      headers: bearer_auth_headers(alice),
      params: {
        transfer: {
          recipient_id: 99_999,
          amount: 50,
          currency: "USD"
        }
      },
      as: :json

    expect(response).to have_http_status(:bad_request)
  end

  it "is idempotent with the same idempotency key" do
    idempotency_key = "transfer-key-#{SecureRandom.uuid}"

    post api_v1_transfers_path,
      headers: bearer_auth_headers(alice, extra: { "Idempotency-Key" => idempotency_key }),
      params: {
        transfer: {
          recipient_id: bob.id,
          amount: 25,
          currency: "USD"
        }
      },
      as: :json

    expect(response).to have_http_status(:created)
    first_response = response.body

    post api_v1_transfers_path,
      headers: bearer_auth_headers(alice, extra: { "Idempotency-Key" => idempotency_key }),
      params: {
        transfer: {
          recipient_id: bob.id,
          amount: 25,
          currency: "USD"
        }
      },
      as: :json

    expect(response).to have_http_status(:created)
    second_response = response.body

    expect(second_response).to eq(first_response)

    transfers = Transaction.unscoped.where(account: alice_account, type: "Transfer")
    expect(transfers.count).to eq(1)
  end
end

