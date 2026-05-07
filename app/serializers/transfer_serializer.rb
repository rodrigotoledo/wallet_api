class TransferSerializer
  include JSONAPI::Serializer

  attributes :id, :amount, :currency, :status, :reference, :metadata, :created_at, :updated_at, :type, :balance

  attribute :balance do |transfer|
    transfer.account.reload.balance.to_f
  end

  attribute :recipient do |transfer|
    {
      id: transfer.recipient_user.id,
      email: transfer.recipient_user.email_address
    }
  end
end
