require "rails_helper"

RSpec.describe IdempotencyCleanupJob, type: :job do
  it "deletes only expired idempotency keys" do
    tenant = create(:tenant)
    user = create(:user, tenant:)

    expired = create(:idempotency_key, tenant:, user:, expires_at: 1.hour.ago)
    active = create(:idempotency_key, tenant:, user:, expires_at: 1.hour.from_now)

    described_class.new.perform

    expect(IdempotencyKey.exists?(expired.id)).to be(false)
    expect(IdempotencyKey.exists?(active.id)).to be(true)
  end
end

