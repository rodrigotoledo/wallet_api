FactoryBot.define do
  factory :transaction do
    tenant
    account
    user
    type { "Deposit" }
    amount { 50.00 }
    currency { "USD" }
    status { 1 }
    reference { "DEP-001" }
    metadata { {} }
  end
end