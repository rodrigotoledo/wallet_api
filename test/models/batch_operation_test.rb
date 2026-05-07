require "test_helper"

class BatchOperationTest < ActiveSupport::TestCase
  test "should be valid with valid attributes" do
    batch_operation = batch_operations(:one)
    assert batch_operation.valid?
  end
end
