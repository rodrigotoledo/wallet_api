# Wallet API

Rails API for tenant-scoped wallet operations with authenticated deposits,
withdrawals, batch deposits, and idempotency-key replay.

## Setup

```bash
bundle install
bin/rails db:setup
bin/rails test
```

Optional services:

- Redis is used as a best-effort idempotency cache.
- Sidekiq processes batch deposit jobs.

For local development:

```bash
redis-server
bundle exec sidekiq -C config/sidekiq.yml
bin/rails server
```

## Authentication

The API uses the existing Rails session login. Create or use a user with an
account, then sign in and keep the returned cookie for API requests.

Example using the test fixture user:

```bash
curl -i -c tmp/cookies.txt \
  -X POST http://localhost:3000/session \
  -d "email_address=one@example.com" \
  -d "password=password"
```

Use the cookie jar on the API calls:

```bash
curl -b tmp/cookies.txt http://localhost:3000/api/v1/batch_deposits/1
```

Unauthenticated JSON requests return:

```json
{
  "error": "unauthorized",
  "message": "Authentication required"
}
```

## Idempotency

`POST` endpoints support an `Idempotency-Key` header. The first request stores
the response in the database and attempts to cache it in Redis for 24 hours.
Repeating the same key in the same scope replays the stored response instead of
creating another wallet operation.

Default scope is the authenticated user. You can also pass:

```http
X-Idempotency-Scope: tenant
```

or:

```http
X-Idempotency-Scope: group
```

## Deposit

```bash
curl -b tmp/cookies.txt \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: deposit-001" \
  -X POST http://localhost:3000/api/v1/deposits \
  -d '{
    "deposit": {
      "amount": "25.00",
      "currency": "USD",
      "reference": "manual-deposit-001"
    }
  }'
```

Successful response:

```json
{
  "id": 123,
  "tenant_id": 1,
  "account_id": 1,
  "user_id": 1,
  "amount": "25.0",
  "currency": "USD",
  "status": "completed",
  "reference": "manual-deposit-001"
}
```

## Withdrawal

```bash
curl -b tmp/cookies.txt \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: withdrawal-001" \
  -X POST http://localhost:3000/api/v1/withdrawals \
  -d '{
    "withdrawal": {
      "amount": "10.00",
      "currency": "USD",
      "reference": "manual-withdrawal-001"
    }
  }'
```

If the account does not have enough balance, the API returns `402 Payment
Required`:

```json
{
  "error": "failed",
  "details": ["insufficient_funds"]
}
```

## Batch Deposits

Batch deposits accept up to 100 items. The create endpoint stores a
`BatchOperation` and enqueues `BatchDepositJob`.

```bash
curl -b tmp/cookies.txt \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: batch-deposit-001" \
  -X POST http://localhost:3000/api/v1/batch_deposits \
  -d '{
    "items": [
      {
        "amount": "5.00",
        "currency": "USD",
        "reference": "payroll-001",
        "item_key": "payroll-001"
      },
      {
        "amount": "7.50",
        "currency": "USD",
        "reference": "payroll-002",
        "item_key": "payroll-002"
      }
    ]
  }'
```

Accepted response:

```json
{
  "batch_id": 42,
  "status": "pending",
  "total_items": 2,
  "message": "Batch accepted. /api/v1/batch_deposits/:id for status."
}
```

Poll for results:

```bash
curl -b tmp/cookies.txt \
  http://localhost:3000/api/v1/batch_deposits/42
```

Example completed result:

```json
{
  "id": 42,
  "status": "completed",
  "total_items": 2,
  "processed_items": 2,
  "failed_items": 0,
  "results": [
    {
      "index": 0,
      "item_key": "payroll-001",
      "success": true,
      "transaction_id": 124,
      "amount": "5.0"
    },
    {
      "index": 1,
      "item_key": "payroll-002",
      "success": true,
      "transaction_id": 125,
      "amount": "7.5"
    }
  ],
  "summary": {
    "total": 2,
    "succeeded": 2,
    "failed": 0,
    "completed_at": "2026-05-06T22:30:00Z"
  }
}
```

Each batch item also has item-level idempotency through `item_key`, cached for
24 hours. Retrying a batch item with the same key reuses the previous item
result.

## Authenticated Demo Task

Run a complete authenticated flow against the real HTTP endpoints. Start the
Rails server first:

```bash
bin/rails server
```

Then run:

```bash
bin/rails wallet:demo
```

The task creates a demo tenant, user, and USD account if needed, then uses
`Net::HTTP` to call:

- `POST /session`
- `POST /api/v1/deposits`
- `POST /api/v1/withdrawals`
- `POST /api/v1/batch_deposits`
- `GET /api/v1/batch_deposits/:id`

Batch processing is asynchronous. To see completed batch results, run Sidekiq in
another terminal:

```bash
bundle exec sidekiq -C config/sidekiq.yml
```

For a self-contained demo, process the created batch locally after the endpoint
accepts it:

```bash
PROCESS_BATCH_INLINE=1 bin/rails wallet:demo
```

Use a different server URL if needed:

```bash
BASE_URL=http://localhost:4000 PROCESS_BATCH_INLINE=1 bin/rails wallet:demo
```

## Tests

Run the full suite:

```bash
bin/rails test
```

Run focused tests:

```bash
bin/rails test test/services/deposit_service_test.rb
bin/rails test test/services/withdrawal_service_test.rb
bin/rails test test/controllers/sessions_controller_test.rb
```
