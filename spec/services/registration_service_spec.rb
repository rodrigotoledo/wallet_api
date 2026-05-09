require "rails_helper"

RSpec.describe RegistrationService, type: :service do
  it "creates tenant user and account on success" do
    result = described_class.call(
      email_address: "admin@newcompany.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "New Company"
    )

    expect(result).to be_success
    expect(result.user).to be_present
    expect(result.user).to be_persisted

    user = result.user
    tenant = user.tenant

    expect(tenant).to be_persisted
    expect(tenant.name).to eq("New Company")
    expect(tenant.subdomain).to eq("new-company")
    expect(tenant.status).to eq("active")

    expect(user.email_address).to eq("admin@newcompany.com")
    expect(user).to be_admin
    expect(user.authenticate("password123")).to be_present

    account = Account.find_by(user_id: user.id, tenant_id: tenant.id)
    expect(account).to be_present
    expect(account.balance.to_f).to eq(0.0)
  end

  it "fails with invalid email" do
    result = described_class.call(
      email_address: "",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Company"
    )

    expect(result).not_to be_success
    expect(result.errors[:email_address]).to be_present
    expect(result.user).to be_nil
  end

  it "fails with short password" do
    result = described_class.call(
      email_address: "admin@company.com",
      password: "short",
      password_confirmation: "short",
      tenant_name: "Company"
    )

    expect(result).not_to be_success
    expect(result.errors[:password]).to be_present
  end

  it "fails with mismatched passwords" do
    result = described_class.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password456",
      tenant_name: "Company"
    )

    expect(result).not_to be_success
    expect(result.errors[:password_confirmation]).to be_present
  end

  it "fails with blank tenant name" do
    result = described_class.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: ""
    )

    expect(result).not_to be_success
    expect(result.errors[:tenant_name]).to be_present
  end

  it "generates subdomain from tenant name" do
    result = described_class.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Acme Corporation"
    )

    expect(result).to be_success
    expect(result.user.tenant.subdomain).to eq("acme-corporation")
  end

  it "generates a valid subdomain with special characters" do
    result = described_class.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Company & Co."
    )

    expect(result).to be_success
    subdomain = result.user.tenant.subdomain
    expect(subdomain).to match(/^company-co/)
    expect(subdomain).to match(/^[a-z0-9-]+$/)
  end

  it "makes duplicate subdomains unique" do
    result1 = described_class.call(
      email_address: "admin1@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Acme Corp"
    )

    expect(result1).to be_success
    subdomain1 = result1.user.tenant.subdomain

    result2 = described_class.call(
      email_address: "admin2@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Acme Corp"
    )

    expect(result2).to be_success
    subdomain2 = result2.user.tenant.subdomain

    expect(subdomain2).not_to eq(subdomain1)
    expect(subdomain1).to match(/^acme-corp/)
    expect(subdomain2).to match(/^acme-corp/)
  end

  it "allows user authentication after registration" do
    result = described_class.call(
      email_address: "admin@company.com",
      password: "mypassword123",
      password_confirmation: "mypassword123",
      tenant_name: "Company"
    )

    expect(result).to be_success
    user = result.user

    authenticated_user = User.authenticate_by(
      email_address: "admin@company.com",
      password: "mypassword123"
    )

    expect(authenticated_user.id).to eq(user.id)
  end

  it "allows reusing the same email across different tenants" do
    result1 = described_class.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Company A"
    )

    expect(result1).to be_success

    result2 = described_class.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Company B"
    )

    expect(result2).to be_success
    expect(result2.user.tenant_id).not_to eq(result1.user.tenant_id)
  end

  it "creates a user that belongs to the created tenant" do
    result = described_class.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Company"
    )

    expect(result).to be_success

    user = result.user
    tenant = user.tenant

    expect(user.tenant_id).to be_present
    expect(user.tenant_id).to eq(tenant.id)
  end
end

