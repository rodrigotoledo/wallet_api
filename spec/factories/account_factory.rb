FactoryBot.define do
  factory :account do
    tenant
    user
    currency { "USD" }
    balance { 100.00 }
    lock_version { 0 }
  end
end