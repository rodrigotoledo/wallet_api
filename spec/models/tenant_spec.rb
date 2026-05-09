require 'rails_helper'

RSpec.describe Tenant, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      tenant = create(:tenant)
      expect(tenant).to be_valid
    end
  end
end
