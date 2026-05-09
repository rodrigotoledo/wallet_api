require "rails_helper"

RSpec.describe DepositService, type: :service do
  let!(:tenant) { create(:tenant) }
  let!(:user) { create(:user, tenant:, password: "secret", password_confirmation: "secret") }
  let!(:account) { create(:account, tenant:, user:, currency: "USD", balance: 100.00) }

  it "increases account balance on success" do
    result = described_class.call(user: user, tenant: tenant, amount: 50.00, currency: "USD")

    expect(result).to be_success
    expect(result.transaction).to be_present
    expect(result.transaction).to be_persisted
    expect(result.errors).to be_empty
    expect(account.reload.balance.to_f).to eq(150.00)
  end

  it "creates a completed Deposit transaction with reference" do
    result = described_class.call(
      user: user,
      tenant: tenant,
      amount: 50.00,
      currency: "USD",
      reference: "DEP-001"
    )

    tx = result.transaction
    expect(tx.status).to eq("completed")
    expect(tx.type).to eq("Deposit")
    expect(tx.amount.to_f).to eq(50.00)
    expect(tx.reference).to eq("DEP-001")
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

  it "fails with amount too large" do
    result = described_class.call(user: user, tenant: tenant, amount: 1_000_001, currency: "USD")

    expect(result).not_to be_success
    expect(result.errors).to include("amount too large")
  end

  it "raises RecordNotFound when account not found" do
    other_user = create(:user, tenant:, password: "secret", password_confirmation: "secret")

    expect do
      described_class.call(user: other_user, tenant: tenant, amount: 50.00, currency: "USD")
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "deposits to the correct currency account" do
    eur_account = create(:account, tenant:, user:, currency: "EUR", balance: 200.00)

    result = described_class.call(user: user, tenant: tenant, amount: 75.00, currency: "EUR")

    expect(result).to be_success
    expect(account.reload.balance.to_f).to eq(100.00)
    expect(eur_account.reload.balance.to_f).to eq(275.00)
  end
end

