require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  test "should be valid with valid attributes" do
    transaction = transactions(:one)
    assert transaction.valid?
  end
end
