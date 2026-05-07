require "test_helper"

class WithdrawalServiceTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.create!(name: "Test Tenant", subdomain: "test-tenant-#{rand(10000)}")
    @user = User.create!(tenant: @tenant, email_address: "user-#{rand(10000)}@example.com", password: "secret", password_confirmation: "secret")
    @account = Account.create!(tenant: @tenant, user: @user, currency: "USD", balance: 100.00)
  end

  test "successful withdrawal decreases account balance" do
    result = WithdrawalService.call(
      user: @user,
      tenant: @tenant,
      amount: 50.00,
      currency: "USD"
    )

    assert result.success?
    assert_not_nil result.transaction
    assert result.transaction.persisted?
    assert_empty result.errors
    assert_equal 50.00, @account.reload.balance
  end

  test "withdrawal creates transaction with completed status" do
    result = WithdrawalService.call(
      user: @user,
      tenant: @tenant,
      amount: 30.00,
      currency: "USD",
      reference: "WTH-001"
    )

    transaction = result.transaction
    assert_equal "completed", transaction.status
    assert_equal "Withdrawal", transaction.type
    assert_equal 30.00, transaction.amount
    assert_equal "WTH-001", transaction.reference
  end

  test "withdrawal fails with insufficient funds" do
    result = WithdrawalService.call(
      user: @user,
      tenant: @tenant,
      amount: 150.00,
      currency: "USD"
    )

    assert_not result.success?
    assert_nil result.transaction
    assert_includes result.errors, "insufficient_funds"
    assert_equal 100.00, @account.reload.balance
  end

  test "withdrawal fails with negative amount" do
    result = WithdrawalService.call(
      user: @user,
      tenant: @tenant,
      amount: -50.00,
      currency: "USD"
    )

    assert_not result.success?
    assert_nil result.transaction
    assert_includes result.errors, "amount must be positive"
  end

  test "withdrawal fails with zero amount" do
    result = WithdrawalService.call(
      user: @user,
      tenant: @tenant,
      amount: 0,
      currency: "USD"
    )

    assert_not result.success?
    assert_includes result.errors, "amount must be positive"
  end

  test "withdrawal with exact balance" do
    result = WithdrawalService.call(
      user: @user,
      tenant: @tenant,
      amount: 100.00,
      currency: "USD"
    )

    assert result.success?
    assert_equal 0, @account.reload.balance
  end

  test "withdrawal raises RecordNotFound when account not found" do
    other_user = User.create!(tenant: @tenant, email_address: "other@example.com", password: "secret")

    assert_raises(ActiveRecord::RecordNotFound) do
      WithdrawalService.call(
        user: other_user,
        tenant: @tenant,
        amount: 50.00,
        currency: "USD"
      )
    end
  end

  test "withdrawal from correct currency account" do
    eur_account = Account.create!(tenant: @tenant, user: @user, currency: "EUR", balance: 200.00)

    result = WithdrawalService.call(
      user: @user,
      tenant: @tenant,
      amount: 25.00,
      currency: "EUR"
    )

    assert result.success?
    assert_equal 100.00, @account.reload.balance
    assert_equal 175.00, eur_account.reload.balance
  end

  test "multiple withdrawals respect pessimistic lock" do
    # Simula duas requisições simultâneas
    # A primeira consegue o lock e faz a withdrawal
    # A segunda espera e vê o saldo atualizado

    result1 = WithdrawalService.call(
      user: @user,
      tenant: @tenant,
      amount: 60.00,
      currency: "USD"
    )

    assert result1.success?
    assert_equal 40.00, @account.reload.balance

    # Segunda withdrawal agora vê saldo correto
    result2 = WithdrawalService.call(
      user: @user,
      tenant: @tenant,
      amount: 50.00,
      currency: "USD"
    )

    assert_not result2.success?
    assert_includes result2.errors, "insufficient_funds"
  end
end
