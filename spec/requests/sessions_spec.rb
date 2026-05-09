require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let!(:user) { create(:user) }
  let!(:account) { create(:account, user:, tenant: user.tenant, balance: 10.25, currency: "USD") }

  describe "GET /session/new" do
    it "renders successfully" do
      get new_session_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /session" do
    it "redirects with valid credentials (html)" do
      post session_path, params: { email_address: user.email_address, password: "password" }

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(root_path)
      expect(user.sessions.reload).to exist
    end

    it "returns jwt with valid credentials (json)" do
      post session_path,
        params: { email_address: user.email_address, password: "password" },
        as: :json

      expect(response).to have_http_status(:created)

      body = json
      expect(body["token_type"]).to eq("Bearer")
      expect(body["token"]).to be_present
      expect(JwtService.decode(body["token"])["user_id"]).to eq(user.id)
      expect(body.dig("user", "balance").to_f).to eq(account.balance.to_f)
      expect(body.dig("user", "currency")).to eq(account.currency)
    end

    it "redirects with invalid credentials (html)" do
      post session_path, params: { email_address: user.email_address, password: "wrong" }

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(new_session_path)
      expect(cookies[:session_id]).to be_nil
    end

    it "returns unauthorized with invalid credentials (json)" do
      post session_path,
        params: { email_address: user.email_address, password: "wrong" },
        as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json["error"]).to eq("invalid_credentials")
    end
  end

  describe "DELETE /session" do
    it "terminates the session" do
      session = sign_in_as(user)
      expect(response).to redirect_to(root_path)
      expect(session).to be_present

      delete session_path

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(new_session_path)
      expect(Session.exists?(session.id)).to be(false)
    end
  end
end

