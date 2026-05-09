require 'rails_helper'

RSpec.describe BatchOperation, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      batch_operation = create(:batch_operation)
      expect(batch_operation).to be_valid
    end
  end
end
