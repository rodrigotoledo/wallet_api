require "rails_helper"

RSpec.describe "API::V1::Profiles", type: :request do
  it "returns current user balance and tenant" do
    tenant = create(:tenant)
    user = create(:user, tenant:)
    create(:account, tenant:, user:, balance: 42.50, currency: "USD")

    get api_v1_profile_path,
      headers: bearer_auth_headers(user),
      as: :json

    expect(response).to have_http_status(:ok)

    body = json
    expect(body.dig("user", "id")).to eq(user.id)
    expect(body.dig("user", "balance").to_f).to eq(42.50)
    expect(body.dig("user", "currency")).to eq("USD")
    expect(body.dig("tenant", "id")).to eq(tenant.id)
  end
end

