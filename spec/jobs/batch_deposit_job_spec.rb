require "rails_helper"

RSpec.describe BatchDepositJob, type: :job do
  let!(:tenant) { create(:tenant) }
  let!(:user) { create(:user, tenant:) }
  let!(:account) { create(:account, tenant:, user:, balance: 100.00, currency: "USD") }

  before do
    Rails.cache.clear
  end

  it "is enqueued after creating a batch operation" do
    expect do
      create(
        :batch_operation,
        tenant: tenant,
        user: user,
        total_items: 1,
        items: [ { "amount" => 10.0, "currency" => "USD", "reference" => "ref-1" } ]
      )
    end.to change(BatchDepositJob.jobs, :size).by(1)
  end

  it "processes all items and marks batch as completed" do
    batch = create(
      :batch_operation,
      tenant: tenant,
      user: user,
      total_items: 2,
      items: [
        { "amount" => 10.0, "currency" => "USD", "reference" => "ref-1" },
        { "amount" => 15.5, "currency" => "USD", "reference" => "ref-2" }
      ]
    )

    described_class.new.perform(batch.id)

    batch.reload
    expect(batch.status).to eq("completed")
    expect(batch.processed_items).to eq(2)
    expect(batch.failed_items).to eq(0)
    expect(batch.results.length).to eq(2)
    expect(batch.summary).to include("total" => 2, "succeeded" => 2, "failed" => 0)

    expect(account.reload.balance.to_f).to eq(125.5)
  end

  it "marks batch as partial when some items fail" do
    batch = create(
      :batch_operation,
      tenant: tenant,
      user: user,
      total_items: 2,
      items: [
        { "amount" => 10.0, "currency" => "USD", "reference" => "ref-1" },
        { "amount" => -1.0, "currency" => "USD", "reference" => "bad" }
      ]
    )

    described_class.new.perform(batch.id)

    batch.reload
    expect(batch.status).to eq("partial")
    expect(batch.processed_items).to eq(2)
    expect(batch.failed_items).to eq(1)
    expect(batch.results.count { |r| r["success"] == false || r[:success] == false }).to eq(1)

    # Only the valid deposit should affect balance.
    expect(account.reload.balance.to_f).to eq(110.0)
  end
end

