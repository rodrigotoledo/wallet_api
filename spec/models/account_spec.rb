require 'rails_helper'

RSpec.describe Account, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      account = create(:account)
      expect(account).to be_valid
    end
  end
end
