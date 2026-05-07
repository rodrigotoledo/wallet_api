require "test_helper"

class DepositTest < ActiveSupport::TestCase
  test "should inherit from Transaction" do
    assert_equal Transaction, Deposit.superclass
  end
end
