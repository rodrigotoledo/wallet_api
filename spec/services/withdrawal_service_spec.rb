require "rails_helper"

RSpec.describe WithdrawalService, type: :service do
  let!(:tenant) { create(:tenant) }
  let!(:user) { create(:user, tenant:, password: "secret", password_confirmation: "secret") }
  let!(:account) { create(:account, tenant:, user:, currency: "USD", balance: 100.00) }

  it "decreases account balance on success" do
    result = described_class.call(user: user, tenant: tenant, amount: 50.00, currency: "USD")

    expect(result).to be_success
    expect(result.transaction).to be_present
    expect(result.transaction).to be_persisted
    expect(result.errors).to be_empty
    expect(account.reload.balance.to_f).to eq(50.00)
  end

  it "creates a completed Withdrawal transaction with reference" do
    result = described_class.call(
      user: user,
      tenant: tenant,
      amount: 30.00,
      currency: "USD",
      reference: "WTH-001"
    )

    tx = result.transaction
    expect(tx.status).to eq("completed")
    expect(tx.type).to eq("Withdrawal")
    expect(tx.amount.to_f).to eq(30.00)
    expect(tx.reference).to eq("WTH-001")
  end

  it "fails with insufficient funds" do
    result = described_class.call(user: user, tenant: tenant, amount: 150.00, currency: "USD")

    expect(result).not_to be_success
    expect(result.transaction).to be_nil
    expect(result.errors).to include("insufficient_funds")
    expect(account.reload.balance.to_f).to eq(100.00)
  end

  it "fails with negative amount" do
    result = described_class.call(user: user, tenant: tenant, amount: -50.00, currency: "USD")

    expect(result).not_to be_success
    expect(result.transaction).to be_nil
    expect(result.errors).to include("amount must be positive")
  end

  it "fails with zero amount" do
    result = described_class.call(user: user, tenant: tenant, amount: 0, currency: "USD")

    expect(result).not_to be_success
    expect(result.errors).to include("amount must be positive")
  end

  it "allows withdrawing the exact balance" do
    result = described_class.call(user: user, tenant: tenant, amount: 100.00, currency: "USD")

    expect(result).to be_success
    expect(account.reload.balance.to_f).to eq(0.0)
  end

  it "raises RecordNotFound when account not found" do
    other_user = create(:user, tenant:, password: "secret", password_confirmation: "secret")

    expect do
      described_class.call(user: other_user, tenant: tenant, amount: 50.00, currency: "USD")
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "withdraws from the correct currency account" do
    eur_account = create(:account, tenant:, user:, currency: "EUR", balance: 200.00)

    result = described_class.call(user: user, tenant: tenant, amount: 25.00, currency: "EUR")

    expect(result).to be_success
    expect(account.reload.balance.to_f).to eq(100.00)
    expect(eur_account.reload.balance.to_f).to eq(175.00)
  end

  it "does not allow a second withdrawal if funds become insufficient" do
    result1 = described_class.call(user: user, tenant: tenant, amount: 60.00, currency: "USD")

    expect(result1).to be_success
    expect(account.reload.balance.to_f).to eq(40.00)

    result2 = described_class.call(user: user, tenant: tenant, amount: 50.00, currency: "USD")

    expect(result2).not_to be_success
    expect(result2.errors).to include("insufficient_funds")
  end
end

