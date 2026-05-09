require "rails_helper"

RSpec.describe TransferProcessorJob, type: :job do
  let!(:tenant) { create(:tenant) }
  let!(:alice) { create(:user, tenant:, email_address: "alice-job@example.com") }
  let!(:bob) { create(:user, tenant:, email_address: "bob-job@example.com") }
  let!(:alice_account) { create(:account, tenant:, user: alice, balance: 100.00, currency: "USD") }
  let!(:bob_account) { create(:account, tenant:, user: bob, balance: 50.00, currency: "USD") }

  it "successfully processes a transfer" do
    transfer_tx = alice_account.transactions.create!(
      type: "Transfer",
      tenant: tenant,
      user: alice,
      recipient_account: bob_account,
      recipient_user: bob,
      amount: 50.0,
      currency: "USD",
      status: :pending
    )

    deposit_tx = bob_account.transactions.create!(
      type: "Deposit",
      tenant: tenant,
      user: bob,
      amount: 50.0,
      currency: "USD",
      status: :pending
    )

    initial_alice_balance = alice_account.balance
    initial_bob_balance = bob_account.balance

    described_class.new.perform(transfer_tx.id)

    transfer_tx.reload
    deposit_tx.reload
    alice_account.reload
    bob_account.reload

    expect(transfer_tx.status).to eq("completed")
    expect(deposit_tx.status).to eq("completed")
    expect(alice_account.balance).to eq(initial_alice_balance - 50.0)
    expect(bob_account.balance).to eq(initial_bob_balance + 50.0)
  end

  it "fails transfer when insufficient funds" do
    transfer_tx = alice_account.transactions.create!(
      type: "Transfer",
      tenant: tenant,
      user: alice,
      recipient_account: bob_account,
      recipient_user: bob,
      amount: alice_account.balance + 100.0,
      currency: "USD",
      status: :pending
    )

    deposit_tx = bob_account.transactions.create!(
      type: "Deposit",
      tenant: tenant,
      user: bob,
      amount: alice_account.balance + 100.0,
      currency: "USD",
      status: :pending
    )

    described_class.new.perform(transfer_tx.id)

    transfer_tx.reload
    deposit_tx.reload

    expect(transfer_tx.status).to eq("failed")
    expect(deposit_tx.status).to eq("failed")
    expect(transfer_tx.metadata["error_reason"]).to eq("insufficient_funds")
    expect(deposit_tx.metadata["error_reason"]).to eq("insufficient_funds")
  end

  it "skips already processed transactions" do
    transfer_tx = alice_account.transactions.create!(
      type: "Transfer",
      tenant: tenant,
      user: alice,
      recipient_account: bob_account,
      recipient_user: bob,
      amount: 50.0,
      currency: "USD",
      status: :completed
    )

    described_class.new.perform(transfer_tx.id)

    transfer_tx.reload
    expect(transfer_tx.status).to eq("completed")
  end
end

