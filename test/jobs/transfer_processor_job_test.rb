require "test_helper"

class TransferProcessorJobTest < ActiveSupport::TestCase
  setup do
    @tenant = tenants(:demo)
    @alice = users(:alice)
    @bob = users(:bob)
    @alice_account = @alice.account
    @bob_account = @bob.account
  end

  test "successfully processes a transfer" do
    # Create pending transactions
    transfer_transaction = @alice_account.transactions.create!(
      type: "Transfer",
      tenant: @tenant,
      user: @alice,
      recipient_account: @bob_account,
      recipient_user: @bob,
      amount: 50.0,
      currency: "USD",
      status: :pending
    )

    deposit_transaction = @bob_account.transactions.create!(
      type: "Deposit",
      tenant: @tenant,
      user: @bob,
      amount: 50.0,
      currency: "USD",
      status: :pending
    )

    # Initial balances
    initial_alice_balance = @alice_account.balance
    initial_bob_balance = @bob_account.balance

    # Process the transfer
    TransferProcessorJob.new.perform(transfer_transaction.id)

    # Reload data
    transfer_transaction.reload
    deposit_transaction.reload
    @alice_account.reload
    @bob_account.reload

    # Assertions
    assert_equal "completed", transfer_transaction.status
    assert_equal "completed", deposit_transaction.status
    assert_equal initial_alice_balance - 50.0, @alice_account.balance
    assert_equal initial_bob_balance + 50.0, @bob_account.balance
  end

  test "fails transfer when insufficient funds" do
    # Create pending transactions with amount larger than balance
    transfer_transaction = @alice_account.transactions.create!(
      type: "Transfer",
      tenant: @tenant,
      user: @alice,
      recipient_account: @bob_account,
      recipient_user: @bob,
      amount: @alice_account.balance + 100.0, # More than available
      currency: "USD",
      status: :pending
    )

    deposit_transaction = @bob_account.transactions.create!(
      type: "Deposit",
      tenant: @tenant,
      user: @bob,
      amount: @alice_account.balance + 100.0,
      currency: "USD",
      status: :pending
    )

    # Process the transfer (should fail)
    TransferProcessorJob.new.perform(transfer_transaction.id)

    # Reload data
    transfer_transaction.reload
    deposit_transaction.reload

    # Assertions
    assert_equal "failed", transfer_transaction.status
    assert_equal "failed", deposit_transaction.status
    assert_equal "insufficient_funds", transfer_transaction.metadata["error_reason"]
    assert_equal "insufficient_funds", deposit_transaction.metadata["error_reason"]
  end

  test "skips already processed transactions" do
    # Create completed transaction
    transfer_transaction = @alice_account.transactions.create!(
      type: "Transfer",
      tenant: @tenant,
      user: @alice,
      recipient_account: @bob_account,
      recipient_user: @bob,
      amount: 50.0,
      currency: "USD",
      status: :completed
    )

    # Process again (should be skipped)
    TransferProcessorJob.new.perform(transfer_transaction.id)

    # Transaction should remain completed
    transfer_transaction.reload
    assert_equal "completed", transfer_transaction.status
  end
end
