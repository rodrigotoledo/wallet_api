require "test_helper"

class ApplicationRecordTest < ActiveSupport::TestCase
  test "should be abstract class" do
    assert ApplicationRecord.abstract_class?
  end
end
