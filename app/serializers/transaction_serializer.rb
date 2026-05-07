class TransactionSerializer
  include JSONAPI::Serializer

  attributes :id, :amount, :currency, :status, :reference, :metadata, :created_at, :updated_at, :type, :balance

  attribute :balance do |transaction|
    transaction.account.balance.to_f
  end
end
