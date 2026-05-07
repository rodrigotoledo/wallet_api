class DepositService
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
      # Pessimistic lock: prevents concurrent deposits from reading stale balance
      account = Account.lock.find_by!(
        tenant: @tenant,
        user:   @user,
        currency: @currency
      )

      transaction = account.transactions.create!(
        type:      "Deposit",
        tenant:    @tenant,
        user:      @user,
        amount:    @amount,
        currency:  @currency,
        status:    :pending,
        reference: @reference
      )

      account.increment!(:balance, @amount)
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
    raise ArgumentError, "amount too large" if @amount > 1_000_000
  end
end
