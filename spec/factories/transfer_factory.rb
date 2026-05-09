FactoryBot.define do
  factory :transfer do
    tenant
    account
    user
    recipient_account { create(:account) }
    recipient_user { create(:user) }
    type { "Transfer" }
    amount { 50.00 }
    currency { "USD" }
    status { 1 }
    reference { "TRF-001" }
    metadata { {} }
  end
end