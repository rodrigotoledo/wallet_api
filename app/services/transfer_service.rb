class TransferService
  def self.call(...)
    new(...).call
  end

  def initialize(sender:, recipient:, tenant:, amount:, currency: "USD", reference: nil)
    @sender    = sender
    @recipient = recipient
    @tenant    = tenant
    @amount    = amount.to_d
    @currency  = currency
    @reference = reference
  end

  def call
    validate_transfer!

    sender_transaction = nil
    ActiveRecord::Base.transaction do
      # Check sender has sufficient funds (preliminary check)
      if @sender_account.balance < @amount
        return ServiceResult.new(
          success?: false,
          transaction: nil,
          errors: [ "insufficient_funds" ]
        )
      end

      # Create transfer transaction for sender (debit)
      sender_transaction = @sender_account.transactions.create!(
        type:               "Transfer",
        tenant:             @tenant,
        user:               @sender,
        recipient_account:  @recipient_account,
        recipient_user:     @recipient,
        amount:             @amount,
        currency:           @currency,
        status:             :pending,
        reference:          @reference
      )

      # Create deposit transaction for recipient (credit)
      recipient_transaction = @recipient_account.transactions.create!(
        type:               "Deposit",
        tenant:             @tenant,
        user:               @recipient,
        amount:             @amount,
        currency:           @currency,
        status:             :pending,
        reference:          @reference
      )
    end

    # Queue job to process the transfer asynchronously (after transaction commits)
    TransferProcessorJob.perform_async(sender_transaction.id)

    ServiceResult.new(success?: true, transaction: sender_transaction, errors: [])
  rescue ActiveRecord::RecordInvalid => e
    ServiceResult.new(success?: false, transaction: nil, errors: e.record.errors.full_messages)
  rescue ActiveRecord::RecordNotFound => e
    ServiceResult.new(success?: false, transaction: nil, errors: [ e.message ])
  rescue ArgumentError => e
    ServiceResult.new(success?: false, transaction: nil, errors: [ e.message ])
  end

  private

  def validate_transfer!
    raise ArgumentError, "amount must be positive" unless @amount > 0
    raise ArgumentError, "amount too large" if @amount > 1_000_000
    raise ArgumentError, "sender and recipient must be different" if @sender == @recipient

    @sender_account = Account.find_by!(
      tenant: @tenant,
      user:   @sender,
      currency: @currency
    )

    @recipient_account = Account.find_by!(
      tenant: @tenant,
      user:   @recipient,
      currency: @currency
    )
  end
end
