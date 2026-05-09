FactoryBot.define do
  factory :session do
    user
    user_agent { "Rails test" }
    ip_address { "127.0.0.1" }
  end
end