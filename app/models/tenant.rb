class Tenant < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :accounts, dependent: :destroy
  has_many :transactions, dependent: :destroy

  validates :name, :subdomain, presence: true
  validates :subdomain, uniqueness: true
end
