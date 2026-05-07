class DepositSerializer
  include JSONAPI::Serializer

  attributes :id, :amount, :currency, :status, :reference, :metadata, :created_at, :updated_at, :type, :balance

  attribute :balance do |deposit|
    deposit.account.balance.to_f
  end

  attribute :type do |deposit|
    'Deposit'
  end
end
