require "rails_helper"

RSpec.describe "Registrations", type: :request do
  def register!(email: "admin@company.com", password: "password123", password_confirmation: password, tenant_name: "Company")
    post registrations_path,
      params: {
        registration: {
          email_address: email,
          password: password,
          password_confirmation: password_confirmation,
          tenant_name: tenant_name
        }
      },
      as: :json
  end

  it "creates tenant user and account with valid parameters" do
    register!(email: "newadmin@company.com", tenant_name: "New Company")

    expect(response).to have_http_status(:created)

    body = json
    expect(body["token_type"]).to eq("Bearer")
    expect(body["token"]).to be_present
    expect(body.dig("user", "email_address")).to eq("newadmin@company.com")
    expect(body.dig("user", "balance").to_f).to eq(0.0)
    expect(body.dig("user", "currency")).to eq("USD")
    expect(body["tenant"]).to be_present
    expect(body.dig("tenant", "name")).to eq("New Company")
    expect(body.dig("tenant", "subdomain")).to be_present

    tenant = Tenant.find(body.dig("tenant", "id"))
    expect(tenant.name).to eq("New Company")
    expect(tenant.subdomain).to eq("new-company")

    user = User.find(body.dig("user", "id"))
    expect(user.tenant_id).to eq(tenant.id)
    expect(user).to be_admin

    account = Account.find_by!(user_id: user.id, tenant_id: tenant.id)
    expect(account.balance.to_f).to eq(0.0)
  end

  it "generates unique subdomain when duplicate exists" do
    Tenant.create!(name: "Company", subdomain: "company")

    register!(email: "admin2@company.com", tenant_name: "Company")

    expect(response).to have_http_status(:created)
    new_subdomain = json.dig("tenant", "subdomain")
    expect(new_subdomain).not_to eq("company")
    expect(new_subdomain).to match(/^company-\d+$/)
  end

  it "fails with invalid email" do
    register!(email: "", tenant_name: "Company")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json["error"]).to eq("registration_failed")
    expect(json.dig("errors", "email_address")).to be_present
  end

  it "fails with short password" do
    register!(password: "pass", password_confirmation: "pass")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json.dig("errors", "password")).to be_present
  end

  it "fails with mismatched passwords" do
    register!(password_confirmation: "password456")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json.dig("errors", "password_confirmation")).to be_present
  end

  it "fails with blank tenant name" do
    register!(tenant_name: "")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json.dig("errors", "tenant_name")).to be_present
  end

  it "returns a jwt token that decodes to the created user" do
    register!(email: "admin@company.com", tenant_name: "My Company")

    body = json
    token = body["token"]
    user_id = body.dig("user", "id")
    tenant_id = body.dig("tenant", "id")

    decoded = JwtService.decode(token)
    expect(decoded["user_id"]).to eq(user_id)

    user = User.find(user_id)
    expect(user.tenant_id).to eq(tenant_id)
  end
end

