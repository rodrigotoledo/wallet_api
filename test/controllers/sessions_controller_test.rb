require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert @user.sessions.exists?
  end

  test "create with valid json credentials returns jwt" do
    post session_path,
      params: { email_address: @user.email_address, password: "password" },
      as: :json

    assert_response :created

    body = JSON.parse(response.body)
    assert_equal "Bearer", body["token_type"]
    assert body["token"].present?
    assert_equal @user.id, JwtService.decode(body["token"])["user_id"]
    assert_equal @user.account.balance.to_f, body["user"]["balance"].to_f
    assert_equal @user.account.currency, body["user"]["currency"]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "create with invalid json credentials returns unauthorized" do
    post session_path,
      params: { email_address: @user.email_address, password: "wrong" },
      as: :json

    assert_response :unauthorized
    assert_equal "invalid_credentials", JSON.parse(response.body)["error"]
  end

  test "destroy" do
    session = sign_in_as(User.take)

    delete session_path

    assert_redirected_to new_session_path
    assert_not Session.exists?(session.id)
  end
end
