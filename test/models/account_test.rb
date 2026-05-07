require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "should be valid with valid attributes" do
    account = accounts(:one)
    assert account.valid?
  end
end
