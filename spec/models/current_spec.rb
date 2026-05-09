require 'rails_helper'

RSpec.describe Current, type: :model do
  let(:session) { create(:session) }

  describe 'session management' do
    it 'sets and gets session' do
      Current.session = session
      expect(Current.session).to eq(session)
    end

    it 'delegates user to session' do
      Current.session = session
      expect(Current.user).to eq(session.user)
    end
  end
end
