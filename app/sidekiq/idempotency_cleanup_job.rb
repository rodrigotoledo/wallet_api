class IdempotencyCleanupJob
  include Sidekiq::Job

  sidekiq_options retry: 3

  def perform
    IdempotencyKey.expired.delete_all
  end
end
