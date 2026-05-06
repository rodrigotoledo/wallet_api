class IdempotencyKey < ApplicationRecord
  belongs_to :tenant
  belongs_to :user
end
