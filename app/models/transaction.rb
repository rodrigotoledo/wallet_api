class Transaction < ApplicationRecord
  acts_as_tenant :tenant
  include TransactionTypes

  belongs_to :account
  belongs_to :user
  belongs_to :recipient_account, class_name: 'Account', optional: true
  belongs_to :recipient_user, class_name: 'User', optional: true

  enum :status, { pending: 0, completed: 1, failed: 2 }

  validates :amount, numericality: { greater_than: 0 }
  validates :type, inclusion: { in: %w[Deposit Withdrawal Transfer] }
end
