require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "create with valid parameters creates tenant user and account" do
    post registrations_path,
      params: {
        registration: {
          email_address: "newadmin@company.com",
          password: "password123",
          password_confirmation: "password123",
          tenant_name: "New Company"
        }
      },
      as: :json

    assert_response :created

    body = JSON.parse(response.body)
    assert_equal "Bearer", body["token_type"]
    assert body["token"].present?
    assert_equal "newadmin@company.com", body["user"]["email_address"]
    assert_equal 0.0, body["user"]["balance"].to_f
    assert_equal "USD", body["user"]["currency"]
    assert body["tenant"].present?
    assert_equal "New Company", body["tenant"]["name"]
    assert body["tenant"]["subdomain"].present?

    # Verify tenant was created
    tenant = Tenant.find(body["tenant"]["id"])
    assert_equal "New Company", tenant.name
    assert_equal "new-company", tenant.subdomain

    # Verify user was created as admin
    user = User.find(body["user"]["id"])
    assert_equal tenant.id, user.tenant_id
    assert user.admin?

    # Verify account was created
    account = Account.find_by(user_id: user.id, tenant_id: tenant.id)
    assert_equal 0.0, account.balance
  end

  test "create with duplicate subdomain generates unique subdomain" do
    tenant1 = Tenant.create!(name: "Company", subdomain: "company")

    post registrations_path,
      params: {
        registration: {
          email_address: "admin@company.com",
          password: "password123",
          password_confirmation: "password123",
          tenant_name: "Company"
        }
      },
      as: :json

    assert_response :created

    body = JSON.parse(response.body)
    new_subdomain = body["tenant"]["subdomain"]
    assert_not_equal "company", new_subdomain
    assert_match /^company-\d+$/, new_subdomain
  end

  test "create with invalid email fails" do
    post registrations_path,
      params: {
        registration: {
          email_address: "",
          password: "password123",
          password_confirmation: "password123",
          tenant_name: "Company"
        }
      },
      as: :json

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)
    assert_equal "registration_failed", body["error"]
    assert body["errors"]["email_address"].present?
  end

  test "create with short password fails" do
    post registrations_path,
      params: {
        registration: {
          email_address: "admin@company.com",
          password: "pass",
          password_confirmation: "pass",
          tenant_name: "Company"
        }
      },
      as: :json

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)
    assert body["errors"]["password"].present?
  end

  test "create with mismatched passwords fails" do
    post registrations_path,
      params: {
        registration: {
          email_address: "admin@company.com",
          password: "password123",
          password_confirmation: "password456",
          tenant_name: "Company"
        }
      },
      as: :json

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)
    assert body["errors"]["password_confirmation"].present?
  end

  test "create with blank tenant name fails" do
    post registrations_path,
      params: {
        registration: {
          email_address: "admin@company.com",
          password: "password123",
          password_confirmation: "password123",
          tenant_name: ""
        }
      },
      as: :json

    assert_response :unprocessable_entity

    body = JSON.parse(response.body)
    assert body["errors"]["tenant_name"].present?
  end

  test "jwt token can be used for authenticated requests" do
    # First create account
    post registrations_path,
      params: {
        registration: {
          email_address: "admin@company.com",
          password: "password123",
          password_confirmation: "password123",
          tenant_name: "My Company"
        }
      },
      as: :json

    body = JSON.parse(response.body)
    token = body["token"]
    user_id = body["user"]["id"]
    tenant_id = body["tenant"]["id"]

    # Use token to decode and verify user
    decoded = JwtService.decode(token)
    assert_equal user_id, decoded["user_id"]

    # Verify user has correct tenant
    user = User.find(user_id)
    assert_equal tenant_id, user.tenant_id
  end
end
