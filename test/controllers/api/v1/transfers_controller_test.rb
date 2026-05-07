require "test_helper"

class Api::V1::TransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @tenant = tenants(:demo)
    @alice = users(:alice)
    @bob = users(:bob)
    @alice_account = accounts(:alice_account)
    @bob_account = accounts(:bob_account)
  end

  test "creates transfer between users" do
    initial_alice_balance = @alice_account.balance
    initial_bob_balance = @bob_account.balance

    assert_difference "@alice_account.reload.balance", -50 do
      assert_difference "@bob_account.reload.balance", 50 do
        post api_v1_transfers_path,
          headers: { "Authorization" => "Bearer #{JwtService.encode(@alice)}" },
          params: {
            transfer: {
              recipient_id: @bob.id,
              amount: 50,
              currency: "USD"
            }
          },
          as: :json
      end
    end

    assert_response :created

    body = jsonapi_response
    assert_equal "Transfer", body["type"]
    assert_equal 50, body["amount"].to_f
    assert_equal "completed", body["status"]
    assert_equal @alice_account.reload.balance.to_f, body["balance"]

    # Check recipient info
    assert_equal @bob.id, body["recipient"]["id"]
    assert_equal @bob.email_address, body["recipient"]["email"]

    # Verify transfer debit and recipient deposit were created
    alice_transaction = Transaction.find_by(account: @alice_account, type: "Transfer")
    bob_transaction = Transaction.find_by(account: @bob_account, type: "Deposit")

    assert alice_transaction
    assert bob_transaction
    assert_equal "completed", alice_transaction.status
    assert_equal "completed", bob_transaction.status
    assert_equal @bob, alice_transaction.recipient_user
  end

  test "fails with insufficient funds" do
    post api_v1_transfers_path,
      headers: { "Authorization" => "Bearer #{JwtService.encode(@alice)}" },
      params: {
        transfer: {
          recipient_id: @bob.id,
          amount: 2000, # More than Alice has
          currency: "USD"
        }
      },
      as: :json

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)
    assert_equal "unprocessable_entity", body["error"]
    assert_includes body["details"], "insufficient_funds"
  end

  test "fails when transferring to self" do
    post api_v1_transfers_path,
      headers: { "Authorization" => "Bearer #{JwtService.encode(@alice)}" },
      params: {
        transfer: {
          recipient_id: @alice.id, # Same as sender
          amount: 50,
          currency: "USD"
        }
      },
      as: :json

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)
    assert_equal "unprocessable_entity", body["error"]
    assert_includes body["details"], "sender and recipient must be different"
  end

  test "fails with invalid recipient" do
    post api_v1_transfers_path,
      headers: { "Authorization" => "Bearer #{JwtService.encode(@alice)}" },
      params: {
        transfer: {
          recipient_id: 99999, # Non-existent user
          amount: 50,
          currency: "USD"
        }
      },
      as: :json

    assert_response :bad_request
  end

  test "handles idempotent transfers" do
    idempotency_key = "transfer-key-#{SecureRandom.uuid}"

    # First request
    post api_v1_transfers_path,
      headers: {
        "Authorization" => "Bearer #{JwtService.encode(@alice)}",
        "Idempotency-Key" => idempotency_key
      },
      params: {
        transfer: {
          recipient_id: @bob.id,
          amount: 25,
          currency: "USD"
        }
      },
      as: :json

    assert_response :created
    first_response = response.body

    # Second request with same idempotency key
    post api_v1_transfers_path,
      headers: {
        "Authorization" => "Bearer #{JwtService.encode(@alice)}",
        "Idempotency-Key" => idempotency_key
      },
      params: {
        transfer: {
          recipient_id: @bob.id,
          amount: 25,
          currency: "USD"
        }
      },
      as: :json

    assert_response :created
    second_response = response.body

    # Should get same response
    assert_equal first_response, second_response

    # Should only have created one transfer
    transfers = Transaction.unscoped.where(account: @alice_account, type: "Transfer")
    assert_equal 1, transfers.count
  end
end
