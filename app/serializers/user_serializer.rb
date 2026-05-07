class UserSerializer
  include JSONAPI::Serializer

  attributes :id, :email_address, :tenant_id, :balance, :currency

  attribute :name do |user|
    user.email_address
  end

  attribute :balance do |user|
    user.account&.balance.to_f
  end

  attribute :currency do |user|
    user.account&.currency || "USD"
  end
end
