class IdempotencyKey < ApplicationRecord
  belongs_to :tenant
  belongs_to :user

  enum :status, { processing: 0, completed: 1, failed: 2 }

  scope :expired, -> { where("expires_at < ?", Time.current) }

  validates :key,   presence: true
  validates :scope, presence: true
end
