class Transaction < ApplicationRecord
  acts_as_tenant :tenant

  belongs_to :account
  belongs_to :user

  enum :status, { pending: 0, completed: 1, failed: 2 }

  validates :amount, numericality: { greater_than: 0 }
  validates :type, inclusion: { in: %w[Deposit Withdrawal] }
end
