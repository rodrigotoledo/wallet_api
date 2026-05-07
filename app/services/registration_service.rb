class RegistrationService
  attr_reader :user, :message, :errors

  def initialize(email_address:, password:, password_confirmation:, tenant_name:)
    @email_address = email_address
    @password = password
    @password_confirmation = password_confirmation
    @tenant_name = tenant_name
    @errors = {}
  end

  def self.call(**args)
    new(**args).call
  end

  def call
    validate_params
    return self if @errors.any?

    create_tenant_and_user
    return self if @errors.any?

    self
  end

  def success?
    @errors.empty?
  end

  private

  def validate_params
    if @email_address.blank?
      @errors[:email_address] = "não pode estar em branco"
    end

    if @password.blank?
      @errors[:password] = "não pode estar em branco"
    elsif @password.length < 8
      @errors[:password] = "deve ter no mínimo 8 caracteres"
    end

    if @password != @password_confirmation
      @errors[:password_confirmation] = "não corresponde à senha"
    end

    if @tenant_name.blank?
      @errors[:tenant_name] = "não pode estar em branco"
    end
  end

  def create_tenant_and_user
    subdomain = generate_subdomain

    @tenant = Tenant.create(
      name: @tenant_name,
      subdomain: subdomain,
      status: "active"
    )

    unless @tenant.persisted?
      @errors.merge!(@tenant.errors.messages)
      return
    end

    # Set tenant context for acts_as_tenant
    ActsAsTenant.with_tenant(@tenant) do
      # Create user and account within tenant context
      @user = User.create(
        email_address: @email_address,
        password: @password,
        password_confirmation: @password_confirmation,
        tenant: @tenant,
        role: :admin
      )

      unless @user.persisted?
        @errors.merge!(@user.errors.messages)
        @tenant.destroy
        return
      end

      # Create account with tenant automatically set by acts_as_tenant
      account = Account.create(balance: 0.0, user: @user)

      unless account.persisted?
        @errors.merge!(account.errors.messages)
        @user.destroy
        @tenant.destroy
      end
    end
  end

  def generate_subdomain
    base = @tenant_name
      .downcase
      .parameterize(separator: "-")
      .slice(0, 50)

    subdomain = base
    counter = 1

    while Tenant.exists?(subdomain: subdomain)
      subdomain = "#{base}-#{counter}"
      counter += 1
    end

    subdomain
  end
end
