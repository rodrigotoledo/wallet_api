require 'rails_helper'

RSpec.describe Withdrawal, type: :model do
  describe 'inheritance' do
    it 'inherits from Transaction' do
      expect(Withdrawal.superclass).to eq(Transaction)
    end
  end
end
