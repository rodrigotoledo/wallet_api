require 'rails_helper'

RSpec.describe Deposit, type: :model do
  describe 'inheritance' do
    it 'inherits from Transaction' do
      expect(Deposit.superclass).to eq(Transaction)
    end
  end
end
