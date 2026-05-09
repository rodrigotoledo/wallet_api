require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'email_address normalization' do
    it 'downcases and strips email_address' do
      user = User.new(email_address: ' DOWNCASED@EXAMPLE.COM ')
      expect(user.email_address).to eq('downcased@example.com')
    end
  end
end
