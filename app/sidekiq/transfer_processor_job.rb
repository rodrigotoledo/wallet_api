class TransferProcessorJob
  include Sidekiq::Job

  sidekiq_options retry: 3, dead: true

  def perform(transfer_transaction_id)
    transfer_transaction = Transaction.find(transfer_transaction_id)

    # Skip if already processed
    return if transfer_transaction.completed? || transfer_transaction.failed?

    # Find the corresponding deposit transaction
    deposit_transaction = Transaction.find_by!(
      tenant: transfer_transaction.tenant,
      user: transfer_transaction.recipient_user,
      type: "Deposit",
      amount: transfer_transaction.amount,
      status: :pending,
      created_at: transfer_transaction.created_at..(transfer_transaction.created_at + 1.minute)
    )

    process_transfer(transfer_transaction, deposit_transaction)
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[TransferProcessor] Transaction not found: #{transfer_transaction_id} - #{e.message}"
    # Don't retry if transaction doesn't exist
    raise e
  rescue => e
    Rails.logger.error "[TransferProcessor] Failed to process transfer #{transfer_transaction_id}: #{e.message}"
    mark_as_failed(transfer_transaction_id)
    raise e
  end

  private

  def process_transfer(transfer_transaction, deposit_transaction)
    ActiveRecord::Base.transaction do
      # Lock both accounts to prevent concurrent modifications
      sender_account = transfer_transaction.account
      recipient_account = deposit_transaction.account

      [sender_account, recipient_account].sort_by(&:id).each(&:lock!)

      # Double-check sender has sufficient funds (in case balance changed)
      if sender_account.balance < transfer_transaction.amount
        mark_as_failed(transfer_transaction.id, deposit_transaction.id, "insufficient_funds")
        return
      end

      # Update balances
      sender_account.decrement!(:balance, transfer_transaction.amount)
      recipient_account.increment!(:balance, transfer_transaction.amount)

      # Mark both transactions as completed
      transfer_transaction.update!(status: :completed)
      deposit_transaction.update!(status: :completed)

      Rails.logger.info "[TransferProcessor] Successfully processed transfer #{transfer_transaction.id}"
    end
  end

  def mark_as_failed(transfer_transaction_id, deposit_transaction_id = nil, error_reason = nil)
    ActiveRecord::Base.transaction do
      transfer_transaction = Transaction.find(transfer_transaction_id)
      transfer_transaction.update!(status: :failed, metadata: { error_reason: error_reason })

      if deposit_transaction_id
        deposit_transaction = Transaction.find(deposit_transaction_id)
        deposit_transaction.update!(status: :failed, metadata: { error_reason: error_reason })
      end
    end
  rescue => e
    Rails.logger.error "[TransferProcessor] Failed to mark transactions as failed: #{e.message}"
  end
end
