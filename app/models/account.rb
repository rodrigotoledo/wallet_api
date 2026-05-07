class Account < ApplicationRecord
  acts_as_tenant :tenant

  belongs_to :user
  has_many :transactions, dependent: :destroy

  validates :balance, numericality: { greater_than_or_equal_to: 0 }
  # this model haves lock_version for optimistic locking, so we can handle concurrent updates to the same account balance
end
