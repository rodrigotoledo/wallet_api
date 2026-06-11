# AGENTS.md

## Cursor Cloud specific instructions

This is a Rails 8.1 JSON API ("Wallet API"): tenant-scoped wallets with JWT auth,
deposits/withdrawals, transfers, and asynchronous batch deposits. Ruby version is
pinned to `4.0.2` via `.tool-versions` and managed with `mise`.

### Services and how to run them

Ruby/PostgreSQL/Redis are already installed in the VM snapshot, and the startup
update script (`mise install` + `bundle install`) refreshes gems. You only need to
start the services below.

- PostgreSQL (required): `sudo pg_ctlcluster 16 main start`. Role is `postgres` /
  password `postgres` on `localhost:5432` (see `config/database.yml`).
- Redis (required for the server, Sidekiq, and idempotency cache): `sudo redis-server --daemonize yes`.
- Rails API server: `bin/rails server -p 3000` (health check: `GET /up` → 200).
- Sidekiq (processes `BatchDepositJob` and idempotency cleanup cron): `bundle exec sidekiq -C config/sidekiq.yml`.
  Without Sidekiq running, batch deposits stay `pending`. Alternatively run the
  demo with `PROCESS_BATCH_INLINE=1` to process batches inline.

### Database

- First-time / reset: `bin/rails db:prepare` creates dev + test DBs and seeds the
  `demo` tenant (users `alice@demo.com` / `bob@demo.com` / `charlie@demo.com`,
  password `password123`). Test DB: `RAILS_ENV=test bin/rails db:test:prepare`.

### Lint / test / build

- Tests use RSpec (the repo migrated off `rails test`): `bundle exec rspec`.
  Sidekiq runs in fake mode under the test env, so Redis is not required for specs.
- Lint: `bin/rubocop` (rubocop-rails-omakase). The repo currently has pre-existing
  style offenses; do not treat them as introduced by your change.
- Security scans: `bin/brakeman --no-pager` and `bin/bundler-audit`.

### Demo / hello-world

`bin/rails wallet:demo` runs a full authenticated flow over real HTTP
(`POST /session`, deposit, withdrawal, batch deposit, poll) against a running
server on `localhost:3000`. It creates a `demo@example.com` user as needed.

### Gotchas

- `mise` provides Ruby; if a fresh non-login shell can't find `ruby`/`bundle`,
  prefix commands with `mise exec --` or ensure `~/.local/bin` is on `PATH`
  (mise activation is in `~/.bashrc`).
- `config/database.yml` hardcodes `host: localhost` and `username/password: postgres`,
  so the local Postgres role must match (the snapshot is already configured this way).
