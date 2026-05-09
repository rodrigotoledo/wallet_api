require "rails_helper"

RSpec.describe TransferService, type: :service do
  let!(:tenant) { create(:tenant) }
  let!(:alice) { create(:user, tenant:, email_address: "alice-service@example.com") }
  let!(:bob) { create(:user, tenant:, email_address: "bob-service@example.com") }
  let!(:alice_account) { create(:account, tenant:, user: alice, balance: 1000.00, currency: "USD") }
  let!(:bob_account) { create(:account, tenant:, user: bob, balance: 500.00, currency: "USD") }

  it "transfers money and creates debit/credit records" do
    Sidekiq::Testing.inline! do
      result = described_class.call(
        sender: alice,
        recipient: bob,
        tenant: tenant,
        amount: 75,
        currency: "USD",
        reference: "service-transfer"
      )

      expect(result).to be_success

      sender_tx = result.transaction.reload
      expect(alice_account.reload.balance.to_f).to eq(925.00)
      expect(bob_account.reload.balance.to_f).to eq(575.00)

      recipient_tx = Transaction.find_by!(account: bob_account, type: "Deposit", reference: "service-transfer")

      expect(sender_tx.type).to eq("Transfer")
      expect(sender_tx.recipient_user).to eq(bob)
      expect(sender_tx.recipient_account).to eq(bob_account)
      expect(sender_tx.status).to eq("completed")
      expect(recipient_tx.status).to eq("completed")
    end
  end

  it "does not change balances when funds are insufficient" do
    result = described_class.call(
      sender: alice,
      recipient: bob,
      tenant: tenant,
      amount: 2_000,
      currency: "USD"
    )

    expect(result).not_to be_success
    expect(result.errors).to include("insufficient_funds")
    expect(alice_account.reload.balance.to_f).to eq(1000.00)
    expect(bob_account.reload.balance.to_f).to eq(500.00)
  end
end

