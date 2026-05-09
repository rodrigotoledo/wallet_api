FactoryBot.define do
  factory :idempotency_key do
    tenant
    user
    scope { "user_1" }
    key { SecureRandom.uuid }
    request_path { "/api/v1/deposits" }
    request_method { "POST" }
    status { 0 }
    response_status { nil }
    response_body { nil }
    locked_at { nil }
    expires_at { 1.day.from_now }
  end
end