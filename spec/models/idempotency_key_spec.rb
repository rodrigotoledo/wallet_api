require 'rails_helper'

RSpec.describe IdempotencyKey, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      idempotency_key = create(:idempotency_key)
      expect(idempotency_key).to be_valid
    end
  end
end
