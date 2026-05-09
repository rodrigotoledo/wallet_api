FactoryBot.define do
  factory :user do
    tenant
    sequence(:email_address) { |n| "user#{n}@example.com" }
    password { "password" }
    password_confirmation { password }
    role { 0 }
  end
end