require "test_helper"

class RegistrationServiceTest < ActiveSupport::TestCase
  test "successful registration creates tenant user and account" do
    result = RegistrationService.call(
      email_address: "admin@newcompany.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "New Company"
    )

    assert result.success?
    assert result.user.present?
    assert result.user.persisted?

    user = result.user
    tenant = user.tenant

    # Verify tenant
    assert tenant.persisted?
    assert_equal "New Company", tenant.name
    assert_equal "new-company", tenant.subdomain
    assert_equal "active", tenant.status

    # Verify user
    assert_equal "admin@newcompany.com", user.email_address
    assert user.admin?
    assert user.authenticate("password123")

    # Verify account
    account = Account.find_by(user_id: user.id, tenant_id: tenant.id)
    assert account.present?
    assert_equal 0.0, account.balance
  end

  test "registration fails with invalid email" do
    result = RegistrationService.call(
      email_address: "",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Company"
    )

    assert_not result.success?
    assert result.errors[:email_address].present?
    assert_nil result.user
  end

  test "registration fails with short password" do
    result = RegistrationService.call(
      email_address: "admin@company.com",
      password: "short",
      password_confirmation: "short",
      tenant_name: "Company"
    )

    assert_not result.success?
    assert result.errors[:password].present?
  end

  test "registration fails with mismatched passwords" do
    result = RegistrationService.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password456",
      tenant_name: "Company"
    )

    assert_not result.success?
    assert result.errors[:password_confirmation].present?
  end

  test "registration fails with blank tenant name" do
    result = RegistrationService.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: ""
    )

    assert_not result.success?
    assert result.errors[:tenant_name].present?
  end

  test "subdomain is generated from tenant name" do
    result = RegistrationService.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Acme Corporation"
    )

    assert result.success?
    assert_equal "acme-corporation", result.user.tenant.subdomain
  end

  test "subdomain handles special characters" do
    result = RegistrationService.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Company & Co."
    )

    assert result.success?
    subdomain = result.user.tenant.subdomain
    assert_match(/^company-co/, subdomain)
    assert_match(/^[a-z0-9-]+$/, subdomain)  # Only lowercase, numbers, hyphens
  end

  test "duplicate subdomains are made unique" do
    # First registration
    result1 = RegistrationService.call(
      email_address: "admin1@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Acme Corp"
    )

    assert result1.success?
    subdomain1 = result1.user.tenant.subdomain

    # Second registration with same tenant name
    result2 = RegistrationService.call(
      email_address: "admin2@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Acme Corp"
    )

    assert result2.success?
    subdomain2 = result2.user.tenant.subdomain

    assert_not_equal subdomain1, subdomain2
    assert_match /^acme-corp/, subdomain1
    assert_match /^acme-corp/, subdomain2
  end

  test "user can authenticate after registration" do
    result = RegistrationService.call(
      email_address: "admin@company.com",
      password: "mypassword123",
      password_confirmation: "mypassword123",
      tenant_name: "Company"
    )

    assert result.success?
    user = result.user

    # Verify authentication works
    authenticated_user = User.authenticate_by(
      email_address: "admin@company.com",
      password: "mypassword123"
    )
    assert_equal user.id, authenticated_user.id
  end

  test "email can be reused in different tenants" do
    result1 = RegistrationService.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Company A"
    )

    assert result1.success?

    # Same email in different tenant is allowed
    result2 = RegistrationService.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Company B"
    )

    assert result2.success?
    assert_not_equal result1.user.tenant_id, result2.user.tenant_id
  end

  test "created user belongs to created tenant" do
    result = RegistrationService.call(
      email_address: "admin@company.com",
      password: "password123",
      password_confirmation: "password123",
      tenant_name: "Company"
    )

    assert result.success?

    user = result.user
    tenant = user.tenant

    assert_equal tenant.id, user.tenant_id
    assert user.tenant_id.present?
  end
end
