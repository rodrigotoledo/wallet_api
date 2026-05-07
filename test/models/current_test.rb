require "test_helper"

class CurrentTest < ActiveSupport::TestCase
  test "should set and get session" do
    session = sessions(:one)
    Current.session = session
    assert_equal session, Current.session
  end

  test "should delegate user to session" do
    session = sessions(:one)
    Current.session = session
    assert_equal session.user, Current.user
  end
end
