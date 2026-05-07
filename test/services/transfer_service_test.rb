require "test_helper"

class TransferServiceTest < ActiveSupport::TestCase
  setup do
    @tenant = tenants(:demo)
    @alice = users(:alice)
    @bob = users(:bob)
    @alice_account = accounts(:alice_account)
    @bob_account = accounts(:bob_account)
  end

  test "transfers money from sender to recipient with debit and credit records" do
    result = TransferService.call(
      sender: @alice,
      recipient: @bob,
      tenant: @tenant,
      amount: 75,
      currency: "USD",
      reference: "service-transfer"
    )

    assert result.success?
    assert_equal 925.00, @alice_account.reload.balance
    assert_equal 575.00, @bob_account.reload.balance

    sender_transaction = result.transaction
    recipient_transaction = Transaction.find_by!(account: @bob_account, type: "Deposit", reference: "service-transfer")

    assert_equal "Transfer", sender_transaction.type
    assert_equal @bob, sender_transaction.recipient_user
    assert_equal @bob_account, sender_transaction.recipient_account
    assert_equal "completed", sender_transaction.status
    assert_equal "completed", recipient_transaction.status
  end

  test "does not change balances when funds are insufficient" do
    result = TransferService.call(
      sender: @alice,
      recipient: @bob,
      tenant: @tenant,
      amount: 2_000,
      currency: "USD"
    )

    assert_not result.success?
    assert_includes result.errors, "insufficient_funds"
    assert_equal 1000.00, @alice_account.reload.balance
    assert_equal 500.00, @bob_account.reload.balance
  end
end
