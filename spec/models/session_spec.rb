require 'rails_helper'

RSpec.describe Session, type: :model do
  describe 'associations' do
    it 'belongs to user' do
      session = create(:session)
      expect(session.user).to be_kind_of(User)
    end
  end
end
