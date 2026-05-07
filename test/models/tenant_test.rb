require "test_helper"

class TenantTest < ActiveSupport::TestCase
  test "should be valid with valid attributes" do
    tenant = tenants(:one)
    assert tenant.valid?
  end
end
