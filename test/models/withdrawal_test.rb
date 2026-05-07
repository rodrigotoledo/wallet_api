require "test_helper"

class WithdrawalTest < ActiveSupport::TestCase
  test "should inherit from Transaction" do
    assert_equal Transaction, Withdrawal.superclass
  end
end
