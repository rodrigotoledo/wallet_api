require "test_helper"

class IdempotencyKeyTest < ActiveSupport::TestCase
  test "should be valid with valid attributes" do
    idempotency_key = idempotency_keys(:one)
    assert idempotency_key.valid?
  end
end
