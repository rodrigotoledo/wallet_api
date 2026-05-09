FactoryBot.define do
  factory :withdrawal do
    tenant
    account
    user
    type { "Withdrawal" }
    amount { 50.00 }
    currency { "USD" }
    status { 1 }
    reference { "WTH-001" }
    metadata { {} }
  end
end