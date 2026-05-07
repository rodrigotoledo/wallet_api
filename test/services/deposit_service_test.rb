require "test_helper"

class DepositServiceTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.create!(name: "Test Tenant", subdomain: "test-tenant-#{rand(10000)}")
    @user = User.create!(tenant: @tenant, email_address: "user-#{rand(10000)}@example.com", password: "secret", password_confirmation: "secret")
    @account = Account.create!(tenant: @tenant, user: @user, currency: "USD", balance: 100.00)
  end

  test "successful deposit increases account balance" do
    result = DepositService.call(
      user: @user,
      tenant: @tenant,
      amount: 50.00,
      currency: "USD"
    )

    assert result.success?
    assert_not_nil result.transaction
    assert result.transaction.persisted?
    assert_empty result.errors
    assert_equal 150.00, @account.reload.balance
  end

  test "deposit creates transaction with completed status" do
    result = DepositService.call(
      user: @user,
      tenant: @tenant,
      amount: 50.00,
      currency: "USD",
      reference: "DEP-001"
    )

    transaction = result.transaction
    assert_equal "completed", transaction.status
    assert_equal "Deposit", transaction.type
    assert_equal 50.00, transaction.amount
    assert_equal "DEP-001", transaction.reference
  end

  test "deposit fails with negative amount" do
    result = DepositService.call(
      user: @user,
      tenant: @tenant,
      amount: -50.00,
      currency: "USD"
    )

    assert_not result.success?
    assert_nil result.transaction
    assert_includes result.errors, "amount must be positive"
  end

  test "deposit fails with zero amount" do
    result = DepositService.call(
      user: @user,
      tenant: @tenant,
      amount: 0,
      currency: "USD"
    )

    assert_not result.success?
    assert_includes result.errors, "amount must be positive"
  end

  test "deposit fails with amount too large" do
    result = DepositService.call(
      user: @user,
      tenant: @tenant,
      amount: 1_000_001,
      currency: "USD"
    )

    assert_not result.success?
    assert_includes result.errors, "amount too large"
  end

  test "deposit raises RecordNotFound when account not found" do
    other_user = User.create!(tenant: @tenant, email_address: "other@example.com", password: "secret")

    assert_raises(ActiveRecord::RecordNotFound) do
      DepositService.call(
        user: other_user,
        tenant: @tenant,
        amount: 50.00,
        currency: "USD"
      )
    end
  end

  test "deposit to correct currency account" do
    eur_account = Account.create!(tenant: @tenant, user: @user, currency: "EUR", balance: 200.00)

    result = DepositService.call(
      user: @user,
      tenant: @tenant,
      amount: 75.00,
      currency: "EUR"
    )

    assert result.success?
    assert_equal 100.00, @account.reload.balance
    assert_equal 275.00, eur_account.reload.balance
  end
end
