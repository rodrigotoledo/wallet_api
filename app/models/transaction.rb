class Transaction < ApplicationRecord
  belongs_to :tenant
  belongs_to :account
  belongs_to :user

   enum status: { pending: 'pending', completed: 'completed', failed: 'failed' }

  validates :amount, numericality: { greater_than: 0 }
  validates :type,   inclusion: { in: %w[Deposit Withdrawal] }
end
