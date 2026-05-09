require "rails_helper"

RSpec.describe "API::V1::TenantUsers", type: :request do
  let!(:tenant) { create(:tenant) }
  let!(:alice) { create(:user, tenant:, email_address: "alice@example.com") }
  let!(:bob) { create(:user, tenant:, email_address: "bob@example.com") }
  let!(:charlie) { create(:user, tenant:, email_address: "charlie@example.com") }

  before do
    create(:account, tenant:, user: alice, balance: 100.00, currency: "USD")
    create(:account, tenant:, user: bob, balance: 500.00, currency: "USD")
    create(:account, tenant:, user: charlie, balance: 250.00, currency: "USD")
  end

  it "returns users from the same tenant excluding current user" do
    get api_v1_tenant_users_path,
      headers: bearer_auth_headers(alice),
      as: :json

    expect(response).to have_http_status(:ok)

    body = json
    expect(body.length).to eq(2)

    user_ids = body.map { |u| u["id"] }
    expect(user_ids).to include(bob.id, charlie.id)
    expect(user_ids).not_to include(alice.id)

    bob_data = body.find { |u| u["id"] == bob.id }
    expect(bob_data["email_address"]).to eq(bob.email_address)
    expect(bob_data["name"]).to eq(bob.email_address)
    expect(bob_data["balance"].to_f).to eq(500.0)
  end

  it "isolates users by tenant" do
    other_tenant = create(:tenant, name: "Other Tenant", subdomain: "other-#{SecureRandom.hex(4)}")
    other_user = create(:user, tenant: other_tenant, email_address: "other@example.com")
    create(:account, tenant: other_tenant, user: other_user, currency: "USD", balance: 100)

    get api_v1_tenant_users_path,
      headers: bearer_auth_headers(alice),
      as: :json

    expect(response).to have_http_status(:ok)
    user_ids = json.map { |u| u["id"] }
    expect(user_ids).not_to include(other_user.id)
  end
end

