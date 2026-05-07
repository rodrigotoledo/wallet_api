Sidekiq::Cron::Job.create(
  name: "Idempotency Cleanup",
  cron: "0 3 * * *",
  class: "IdempotencyCleanupJob"
)
