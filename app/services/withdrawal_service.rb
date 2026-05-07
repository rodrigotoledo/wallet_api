class WithdrawalService
  def self.call(...)
    new(...).call
  end

  def initialize(user:, tenant:, amount:, currency: "USD", reference: nil)
    @user      = user
    @tenant    = tenant
    @amount    = amount.to_d
    @currency  = currency
    @reference = reference
  end

  def call
    validate_amount!

    ActiveRecord::Base.transaction do
      # Pessimistic lock: prevents concurrent withdrawals from reading stale balance
      account = Account.lock.find_by!(
        tenant:   @tenant,
        user:     @user,
        currency: @currency
      )

      if account.balance < @amount
        return ServiceResult.new(
          success?: false,
          transaction: nil,
          errors: [ "insufficient_funds" ]
        )
      end

      transaction = account.transactions.create!(
        type:      "Withdrawal",
        tenant:    @tenant,
        user:      @user,
        amount:    @amount,
        currency:  @currency,
        status:    :pending,
        reference: @reference
      )

      account.decrement!(:balance, @amount)
      transaction.update!(status: :completed)

      ServiceResult.new(success?: true, transaction: transaction, errors: [])
    end
  rescue ActiveRecord::RecordInvalid => e
    ServiceResult.new(success?: false, transaction: nil, errors: e.record.errors.full_messages)
  rescue ArgumentError => e
    ServiceResult.new(success?: false, transaction: nil, errors: [ e.message ])
  end

  private

  def validate_amount!
    raise ArgumentError, "amount must be positive" unless @amount > 0
  end
end
