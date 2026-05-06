class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  belongs_to :tenant
  has_one  :account
  has_many :transactions
  has_many :idempotency_keys

  enum role: { member: 'member', admin: 'admin' }

  validates :email_address, presence: true, uniqueness: { scope: :tenant_id }
end
