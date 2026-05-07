require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "should belong to user" do
    session = sessions(:one)
    assert_kind_of User, session.user
  end
end
