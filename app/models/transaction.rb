class Transaction < ApplicationRecord
  belongs_to :tenant
  belongs_to :account
  belongs_to :user
end
