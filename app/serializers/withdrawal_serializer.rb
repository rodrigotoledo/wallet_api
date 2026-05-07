class WithdrawalSerializer
  include JSONAPI::Serializer

  attributes :id, :amount, :currency, :status, :reference, :metadata, :created_at, :updated_at, :type, :balance

  attribute :balance do |withdrawal|
    withdrawal.account.balance.to_f
  end

  attribute :type do |withdrawal|
    'Withdrawal'
  end
end
