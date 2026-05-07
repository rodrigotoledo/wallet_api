Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }
end

if Rails.env.test?
  require "sidekiq/testing"
  # Use fake mode by default - jobs are queued but not executed
  Sidekiq::Testing.fake!
end
