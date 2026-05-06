Redis.new(
  url:            ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
  connect_timeout: 1,   # fail fast se Redis estiver down
  read_timeout:    1,
  write_timeout:   1
)