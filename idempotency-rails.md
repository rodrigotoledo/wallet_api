# Idempotência em Rails API — Multi-tenant, Batch e Race Conditions

> Guia prático para construir uma API Rails com idempotência real, usando banco de dados como fonte da verdade e Redis como cache.

---

## Índice

1. [Conceito e por que Redis sozinho não basta](#1-conceito)
2. [Arquitetura geral](#2-arquitetura)
3. [Setup inicial do projeto](#3-setup)
4. [Migrations](#4-migrations)
5. [Models](#5-models)
6. [Concern: Idempotent](#6-concern)
7. [Endpoints: Depósito e Retirada](#7-endpoints)
8. [Operações em Lote (Batch)](#8-batch)
9. [Race Conditions — como o banco resolve](#9-race-conditions)
10. [Scopes: user / group / tenant](#10-scopes)
11. [Cleanup e expiração](#11-cleanup)
12. [Testando com curl](#12-testando)
13. [Checklist de produção](#13-checklist)

---

## 1. Conceito

Idempotência significa que chamar a mesma operação **N vezes** produz o **mesmo resultado** que chamar uma vez.

```
POST /deposits  { amount: 100 }  →  cria depósito de R$ 100
POST /deposits  { amount: 100 }  →  retorna o MESMO depósito (não cria novo)
POST /deposits  { amount: 100 }  →  retorna o MESMO depósito
```

O cliente envia um `Idempotency-Key` no header — uma UUID gerada antes de clicar "Confirmar". Se a rede cair e ele tentar de novo, o servidor detecta a key e devolve o resultado original sem reprocessar.

### Por que Redis sozinho não basta

| Cenário | Redis sozinho | Redis + DB |
|---------|--------------|------------|
| Redis reinicia / cai | ❌ perde todas as keys | ✅ DB persiste |
| Deploy da aplicação | ❌ depende da config de persistência | ✅ transparente |
| 3 servidores simultâneos | ⚠️ replication lag pode causar duplicata | ✅ UNIQUE constraint é atômico |
| Race condition (double-click) | ⚠️ depende de lock manual | ✅ DB resolve nativamente |
| Performance | ✅ O(1) | ✅ Redis na frente, DB como fallback |

**Regra:** Redis é cache. PostgreSQL com `UNIQUE constraint` é a garantia real.

---

## 2. Arquitetura

```
Cliente
  │
  │  POST /api/v1/deposits
  │  Headers:
  │    Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
  │    X-Idempotency-Scope: user
  │    Authorization: Bearer <token>
  ▼

┌─────────────────────────────────────┐
│  Middleware / Concern               │
│                                     │
│  1. Extrai tenant + user + key      │
│  2. Checa Redis (rápido)            │
│     └─ HIT → resposta cacheada      │
│     └─ MISS/DOWN → vai ao banco     │
│  3. Banco: find_or_create           │
│     └─ status=completed → replay    │
│     └─ status=processing → 409      │
│     └─ status=failed → permite retry│
│  4. Processa a request              │
│  5. Salva resultado no banco        │
│  6. Escreve no Redis                │
└─────────────────────────────────────┘
  │
  ▼
Service / ActiveRecord
  │
  ▼
PostgreSQL
  ├── tenants
  ├── users
  ├── accounts
  ├── transactions
  └── idempotency_keys  ← fonte da verdade
```

---

## 3. Setup inicial do projeto

```bash
rails new wallet_api --api --database=postgresql
cd wallet_api

# Gemfile
gem 'redis'
gem 'jwt'                    # autenticação
gem 'bcrypt'                 # passwords
gem 'sidekiq'                # background jobs (batch + cleanup)
gem 'sidekiq-cron'           # cron jobs
```

```ruby
# config/initializers/redis.rb
Redis.current = Redis.new(
  url:            ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
  connect_timeout: 1,   # fail fast se Redis estiver down
  read_timeout:    1,
  write_timeout:   1
)
```

---

## 4. Migrations

### Tenants

```ruby
class CreateTenants < ActiveRecord::Migration[7.1]
  def change
    create_table :tenants do |t|
      t.string :name,      null: false
      t.string :subdomain, null: false
      t.string :status,    null: false, default: 'active'
      t.timestamps
    end
    add_index :tenants, :subdomain, unique: true
  end
end
```

### Users

```ruby
class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :email,           null: false
      t.string :password_digest, null: false
      t.string :group_key                    # para scope de grupo
      t.string :role, null: false, default: 'member'
      t.timestamps
    end
    add_index :users, [:tenant_id, :email], unique: true
  end
end
```

### Accounts (carteiras)

```ruby
class CreateAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :accounts do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user,   null: false, foreign_key: true
      t.string  :currency, null: false, default: 'BRL'
      t.decimal :balance,
                null: false,
                default: 0,
                precision: 15,
                scale: 2
      t.integer :lock_version, null: false, default: 0   # optimistic locking
      t.timestamps
    end
    add_index :accounts, [:tenant_id, :user_id, :currency], unique: true
  end
end
```

### Transactions

```ruby
class CreateTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :transactions do |t|
      t.references :tenant,  null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :user,    null: false, foreign_key: true

      t.string  :type,     null: false   # Deposit / Withdrawal
      t.decimal :amount,
                null: false,
                precision: 15,
                scale: 2
      t.string  :currency, null: false, default: 'BRL'
      t.string  :status,   null: false, default: 'pending'
                                         # pending / completed / failed
      t.string  :reference                # chave externa / descrição
      t.jsonb   :metadata, default: {}
      t.timestamps
    end

    add_index :transactions, [:tenant_id, :account_id]
    add_index :transactions, :status
  end
end
```

### Batch Operations

```ruby
class CreateBatchOperations < ActiveRecord::Migration[7.1]
  def change
    create_table :batch_operations do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user,   null: false, foreign_key: true

      t.string  :operation_type, null: false   # batch_deposit / batch_withdrawal
      t.string  :status, null: false, default: 'pending'
                                                # pending/processing/completed/partial/failed
      t.integer :total_items,     null: false, default: 0
      t.integer :processed_items, null: false, default: 0
      t.integer :failed_items,    null: false, default: 0
      t.jsonb   :items,    null: false, default: []   # array dos itens
      t.jsonb   :results,  null: false, default: []   # resultados por item
      t.jsonb   :summary,  null: false, default: {}
      t.timestamps
    end
  end
end
```

### Idempotency Keys (fonte da verdade)

```ruby
class CreateIdempotencyKeys < ActiveRecord::Migration[7.1]
  def change
    create_table :idempotency_keys do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user,   null: false, foreign_key: true

      t.string   :scope,        null: false   # "user_99" | "group_abc" | "tenant"
      t.string   :key,          null: false   # UUID do cliente
      t.string   :request_path, null: false
      t.string   :request_method, null: false, default: 'POST'

      t.integer  :status, null: false, default: 0
                           # 0=processing | 1=completed | 2=failed

      t.integer  :response_status
      t.jsonb    :response_body
      t.datetime :locked_at
      t.datetime :expires_at, null: false
      t.timestamps
    end

    # A GARANTIA REAL — unique no banco, não no Redis
    add_index :idempotency_keys,
              [:tenant_id, :scope, :key],
              unique: true,
              name: 'idx_idempotency_unique'

    add_index :idempotency_keys, :expires_at
    add_index :idempotency_keys, :status
  end
end
```

---

## 5. Models

```ruby
# app/models/tenant.rb
class Tenant < ApplicationRecord
  has_many :users
  has_many :accounts
  has_many :transactions
  has_many :idempotency_keys

  enum status: { active: 'active', suspended: 'suspended' }

  validates :subdomain, presence: true, uniqueness: true
end
```

```ruby
# app/models/user.rb
class User < ApplicationRecord
  include BCrypt

  belongs_to :tenant
  has_one  :account
  has_many :transactions
  has_many :idempotency_keys

  enum role: { member: 'member', admin: 'admin' }

  validates :email, presence: true, uniqueness: { scope: :tenant_id }
  validates :password_digest, presence: true

  def password=(raw)
    self.password_digest = Password.create(raw)
  end

  def authenticate(raw)
    Password.new(password_digest) == raw
  end
end
```

```ruby
# app/models/account.rb
class Account < ApplicationRecord
  belongs_to :tenant
  belongs_to :user
  has_many   :transactions

  validates :balance, numericality: { greater_than_or_equal_to: 0 }

  # Optimistic locking nativo do Rails (lock_version)
  # Lança ActiveRecord::StaleObjectError em conflito
end
```

```ruby
# app/models/transaction.rb
class Transaction < ApplicationRecord
  belongs_to :tenant
  belongs_to :account
  belongs_to :user

  enum status: { pending: 'pending', completed: 'completed', failed: 'failed' }

  validates :amount, numericality: { greater_than: 0 }
  validates :type,   inclusion: { in: %w[Deposit Withdrawal] }

  # STI: Deposit e Withdrawal herdam de Transaction
end

class Deposit < Transaction; end
class Withdrawal < Transaction; end
```

```ruby
# app/models/idempotency_key.rb
class IdempotencyKey < ApplicationRecord
  belongs_to :tenant
  belongs_to :user

  enum status: { processing: 0, completed: 1, failed: 2 }

  scope :expired, -> { where('expires_at < ?', Time.current) }

  validates :key,   presence: true
  validates :scope, presence: true
end
```

---

## 6. Concern: Idempotent

```ruby
# app/controllers/concerns/idempotent.rb
module Idempotent
  extend ActiveSupport::Concern

  IDEMPOTENCY_TTL  = 24.hours
  LOCK_TIMEOUT_SEC = 30

  included do
    before_action :handle_idempotency, if: :idempotency_key_present?
    after_action  :finalize_idempotency, if: :idempotency_key_present?
  end

  private

  # ─── BEFORE ACTION ──────────────────────────────────────────────────

  def handle_idempotency
    # 1. Redis (rápido, best-effort)
    if (cached = read_from_redis)
      @idempotency_replayed = true
      render json: cached[:body], status: cached[:status]
      return
    end

    # 2. Banco (fonte da verdade)
    record = find_or_initialize_idempotency_record
    @idempotency_record = record

    case record.status
    when 'completed'
      write_to_redis(record)           # backfill Redis
      @idempotency_replayed = true
      render json: record.response_body, status: record.response_status

    when 'processing'
      # Outra instância está processando — retorna 409
      render json: {
        error: 'conflict',
        message: 'A request with this idempotency key is already being processed.',
        idempotency_key: idempotency_key
      }, status: :conflict

    when 'failed'
      # Falhou antes — permite retry, reseta para processing
      record.update!(
        status:    :processing,
        locked_at: Time.current
      )
    end
  end

  # ─── AFTER ACTION ───────────────────────────────────────────────────

  def finalize_idempotency
    return if @idempotency_replayed
    return unless @idempotency_record

    if response.status < 500
      @idempotency_record.update!(
        status:          :completed,
        response_status: response.status,
        response_body:   parse_response_body
      )
      write_to_redis(@idempotency_record)
    else
      # Erro 5xx — marca como failed para permitir retry
      @idempotency_record.update!(
        status:    :failed,
        locked_at: nil
      )
    end
  end

  # ─── DB ─────────────────────────────────────────────────────────────

  def find_or_initialize_idempotency_record
    IdempotencyKey.find_or_create_by!(
      tenant: current_tenant,
      scope:  idempotency_scope_key,
      key:    idempotency_key
    ) do |record|
      record.user           = current_user
      record.status         = :processing
      record.locked_at      = Time.current
      record.expires_at     = IDEMPOTENCY_TTL.from_now
      record.request_path   = request.path
      record.request_method = request.method
    end
  rescue ActiveRecord::RecordNotUnique
    # Race condition: dois servidores tentaram criar simultaneamente
    # O UNIQUE constraint garantiu a consistência — buscamos o vencedor
    IdempotencyKey.find_by!(
      tenant: current_tenant,
      scope:  idempotency_scope_key,
      key:    idempotency_key
    )
  end

  # ─── REDIS (best-effort, nunca propaga erro) ────────────────────────

  def read_from_redis
    raw = Redis.current.get(redis_key)
    JSON.parse(raw, symbolize_names: true) if raw
  rescue Redis::BaseError => e
    Rails.logger.warn "[Idempotency] Redis read failed: #{e.message} — falling back to DB"
    nil
  end

  def write_to_redis(record)
    Redis.current.setex(
      redis_key,
      IDEMPOTENCY_TTL.to_i,
      { status: record.response_status, body: record.response_body }.to_json
    )
  rescue Redis::BaseError => e
    Rails.logger.warn "[Idempotency] Redis write failed: #{e.message} — DB is the source of truth"
    nil
  end

  # ─── HELPERS ────────────────────────────────────────────────────────

  def redis_key
    "idempotency:#{current_tenant.id}:#{idempotency_scope_key}:#{idempotency_key}"
  end

  def idempotency_scope_key
    case request.headers['X-Idempotency-Scope']
    when 'group'  then "group_#{current_user.group_key}"
    when 'tenant' then "tenant"
    else               "user_#{current_user.id}"   # default
    end
  end

  def idempotency_key
    request.headers['Idempotency-Key']
  end

  def idempotency_key_present?
    idempotency_key.present?
  end

  def parse_response_body
    JSON.parse(response.body)
  rescue JSON::ParserError
    { raw: response.body }
  end
end
```

---

## 7. Endpoints: Depósito e Retirada

### ApplicationController base

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  include Authentication   # ativa autenticação via sessão
end
```

### Authentication Concern

A autenticação suporta **ambos os métodos**: sessões (web clients) e JWT (mobile/APIs):

```ruby
# app/controllers/concerns/authentication.rb
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    before_action :set_tenant
    helper_method :authenticated?, :current_user, :current_tenant
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session || resume_jwt
    end

    def require_authentication
      authenticated? || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def resume_jwt
      Current.user ||= find_user_from_jwt if jwt_token.present?
    end

    def set_tenant
      Current.tenant = current_user.tenant if current_user
    end

    def current_user
      Current.session&.user || Current.user
    end

    def current_tenant
      Current.tenant
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def jwt_token
      request.headers['Authorization']&.split(' ')&.last
    end

    def find_user_from_jwt
      return unless jwt_token.present?

      payload = JwtService.decode(jwt_token)
      User.find(payload["user_id"])
    rescue => e
      Rails.logger.warn "[Auth] JWT decode failed: #{e.message}"
      nil
    end

    def request_authentication
      if request.format.json?
        render json: { error: "unauthorized", message: "Authentication required" }, status: :unauthorized
      else
        session[:return_to_after_authenticating] = request.url
        redirect_to new_session_path
      end
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
```

**Como funciona:**

| Prioridade | Método | Usado por | Header/Cookie |
|-----------|--------|-----------|---------------|
| 1º | Session | Web clients | `Cookie: session_id=...` |
| 2º | JWT | Mobile/APIs | `Authorization: Bearer <token>` |

Ambos os métodos definem `current_user` e `current_tenant` automaticamente, então os controllers funcionam igual.

### DepositsController

```ruby
# app/controllers/api/v1/deposits_controller.rb
module Api
  module V1
    class DepositsController < ApplicationController
      include Idempotent   # ativa idempotência para este controller

      # POST /api/v1/deposits
      # Headers obrigatórios:
      #   Idempotency-Key: <uuid>
      #   Authorization:   Bearer <token>
      def create
        result = DepositService.call(
          user:    current_user,
          tenant:  current_tenant,
          amount:  deposit_params[:amount],
          currency: deposit_params[:currency] || 'BRL',
          reference: deposit_params[:reference]
        )

        if result.success?
          render json: TransactionSerializer.new(result.transaction),
                 status: :created
        else
          render json: { error: 'unprocessable_entity', details: result.errors },
                 status: :unprocessable_entity
        end
      end

      private

      def deposit_params
        params.require(:deposit).permit(:amount, :currency, :reference)
      end
    end
  end
end
```

### WithdrawalsController

```ruby
# app/controllers/api/v1/withdrawals_controller.rb
module Api
  module V1
    class WithdrawalsController < ApplicationController
      include Idempotent

      # POST /api/v1/withdrawals
      def create
        result = WithdrawalService.call(
          user:    current_user,
          tenant:  current_tenant,
          amount:  withdrawal_params[:amount],
          currency: withdrawal_params[:currency] || 'BRL',
          reference: withdrawal_params[:reference]
        )

        if result.success?
          render json: TransactionSerializer.new(result.transaction),
                 status: :created
        else
          status = result.errors.include?('insufficient_funds') ? :payment_required : :unprocessable_entity
          render json: { error: 'failed', details: result.errors },
                 status: status
        end
      end

      private

      def withdrawal_params
        params.require(:withdrawal).permit(:amount, :currency, :reference)
      end
    end
  end
end
```

### DepositService

```ruby
# app/services/deposit_service.rb
class DepositService
  Result = Struct.new(:success?, :transaction, :errors, keyword_init: true)

  def self.call(...)
    new(...).call
  end

  def initialize(user:, tenant:, amount:, currency: 'BRL', reference: nil)
    @user      = user
    @tenant    = tenant
    @amount    = amount.to_d
    @currency  = currency
    @reference = reference
  end

  def call
    validate_amount!

    ActiveRecord::Base.transaction do
      account = Account.lock('FOR UPDATE').find_by!(   # pessimistic lock
        tenant: @tenant,
        user:   @user,
        currency: @currency
      )

      transaction = account.transactions.create!(
        type:      'Deposit',
        tenant:    @tenant,
        user:      @user,
        amount:    @amount,
        currency:  @currency,
        status:    :pending,
        reference: @reference
      )

      account.increment!(:balance, @amount)
      transaction.update!(status: :completed)

      Result.new(success?: true, transaction: transaction, errors: [])
    end
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, transaction: nil, errors: e.record.errors.full_messages)
  rescue ArgumentError => e
    Result.new(success?: false, transaction: nil, errors: [e.message])
  end

  private

  def validate_amount!
    raise ArgumentError, 'amount must be positive' unless @amount > 0
    raise ArgumentError, 'amount too large' if @amount > 1_000_000
  end
end
```

### WithdrawalService

```ruby
# app/services/withdrawal_service.rb
class WithdrawalService
  Result = Struct.new(:success?, :transaction, :errors, keyword_init: true)

  def self.call(...)
    new(...).call
  end

  def initialize(user:, tenant:, amount:, currency: 'BRL', reference: nil)
    @user      = user
    @tenant    = tenant
    @amount    = amount.to_d
    @currency  = currency
    @reference = reference
  end

  def call
    validate_amount!

    ActiveRecord::Base.transaction do
      # FOR UPDATE: lock pessimista — bloqueia a linha durante a transação
      # Impede que dois withdrawals simultâneos leiam o mesmo saldo
      account = Account.lock('FOR UPDATE').find_by!(
        tenant:   @tenant,
        user:     @user,
        currency: @currency
      )

      if account.balance < @amount
        return Result.new(
          success?: false,
          transaction: nil,
          errors: ['insufficient_funds']
        )
      end

      transaction = account.transactions.create!(
        type:      'Withdrawal',
        tenant:    @tenant,
        user:      @user,
        amount:    @amount,
        currency:  @currency,
        status:    :pending,
        reference: @reference
      )

      account.decrement!(:balance, @amount)
      transaction.update!(status: :completed)

      Result.new(success?: true, transaction: transaction, errors: [])
    end
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, transaction: nil, errors: e.record.errors.full_messages)
  rescue ArgumentError => e
    Result.new(success?: false, transaction: nil, errors: [e.message])
  end

  private

  def validate_amount!
    raise ArgumentError, 'amount must be positive' unless @amount > 0
  end
end
```

---

## 8. Operações em Lote (Batch)

Batch tem uma camada extra de complexidade: cada item do lote precisa de **idempotência própria** e o lote inteiro também precisa ser idempotente.

### BatchDepositsController

```ruby
# app/controllers/api/v1/batch_deposits_controller.rb
module Api
  module V1
    class BatchDepositsController < ApplicationController
      include Idempotent   # o LOTE inteiro é idempotente

      MAX_BATCH_SIZE = 100

      # POST /api/v1/batch_deposits
      # Body:
      # {
      #   "items": [
      #     { "amount": 100.00, "reference": "ref-001", "item_key": "uuid-item-1" },
      #     { "amount": 250.00, "reference": "ref-002", "item_key": "uuid-item-2" }
      #   ]
      # }
      def create
        items = batch_params[:items]

        if items.size > MAX_BATCH_SIZE
          return render json: {
            error: 'too_many_items',
            message: "Maximum #{MAX_BATCH_SIZE} items per batch"
          }, status: :unprocessable_entity
        end

        batch = BatchOperation.create!(
          tenant:         current_tenant,
          user:           current_user,
          operation_type: 'batch_deposit',
          status:         'pending',
          total_items:    items.size,
          items:          items
        )

        # Processa em background para não segurar a connection HTTP
        BatchDepositJob.perform_later(batch.id)

        render json: {
          batch_id:    batch.id,
          status:      batch.status,
          total_items: batch.total_items,
          message:     'Batch accepted. Poll /api/v1/batch_deposits/:id for status.'
        }, status: :accepted
      end

      # GET /api/v1/batch_deposits/:id
      def show
        batch = BatchOperation.find_by!(
          id:     params[:id],
          tenant: current_tenant
        )

        render json: BatchOperationSerializer.new(batch)
      end

      private

      def batch_params
        params.permit(items: [:amount, :currency, :reference, :item_key])
      end
    end
  end
end
```

### BatchDepositJob

```ruby
# app/jobs/batch_deposit_job.rb
class BatchDepositJob < ApplicationJob
  queue_as :default

  def perform(batch_id)
    batch = BatchOperation.find(batch_id)
    batch.update!(status: 'processing')

    results      = []
    failed_count = 0

    batch.items.each_with_index do |item, index|
      result = process_item(batch, item, index)
      results << result
      failed_count += 1 unless result[:success]

      # Atualiza progresso a cada item (útil para polling)
      batch.update!(
        processed_items: index + 1,
        results:         results
      )
    end

    final_status = determine_final_status(results, batch.total_items, failed_count)

    batch.update!(
      status:        final_status,
      failed_items:  failed_count,
      results:       results,
      summary: {
        total:     batch.total_items,
        succeeded: batch.total_items - failed_count,
        failed:    failed_count,
        completed_at: Time.current.iso8601
      }
    )
  end

  private

  def process_item(batch, item, index)
    # Idempotência por item: usa o item_key como chave de idempotência
    # Se o job rodar duas vezes (retry do Sidekiq), não duplica
    item_key     = item['item_key'] || "#{batch.id}-item-#{index}"
    idempotency_record_key = "batch_item:#{batch.tenant_id}:#{item_key}"

    # Checa se este item já foi processado (idempotência do job)
    existing = Rails.cache.read(idempotency_record_key)
    return existing if existing

    result = DepositService.call(
      user:      batch.user,
      tenant:    batch.tenant,
      amount:    item['amount'],
      currency:  item['currency'] || 'BRL',
      reference: item['reference']
    )

    response = if result.success?
      {
        index:          index,
        item_key:       item_key,
        success:        true,
        transaction_id: result.transaction.id,
        amount:         result.transaction.amount
      }
    else
      {
        index:    index,
        item_key: item_key,
        success:  false,
        errors:   result.errors
      }
    end

    # Cacheia por 24h para idempotência do job
    Rails.cache.write(idempotency_record_key, response, expires_in: 24.hours)
    response

  rescue => e
    Rails.logger.error "[BatchDeposit] Item #{index} failed: #{e.message}"
    { index: index, item_key: item_key, success: false, errors: [e.message] }
  end

  def determine_final_status(results, total, failed_count)
    if failed_count == 0           then 'completed'
    elsif failed_count == total    then 'failed'
    else                                'partial'    # alguns falharam
    end
  end
end
```

---

## 9. Race Conditions — como o banco resolve

### Cenário: double-click (dois requests simultâneos, mesma key)

```
Tempo →
T1:  Servidor A lê Redis       → miss
T2:  Servidor B lê Redis       → miss (ainda não foi escrito)
T3:  Servidor A tenta INSERT   → ✅ sucesso, status=processing
T4:  Servidor B tenta INSERT   → ❌ RecordNotUnique (UNIQUE constraint)
T5:  Servidor B faz SELECT     → encontra o record do A, status=processing
T6:  Servidor B retorna 409    ← cliente sabe que está sendo processado
T7:  Servidor A conclui        → status=completed, response salvo
T8:  Cliente retenta           → Servidor C lê Redis ou banco → replay ✅
```

O `rescue ActiveRecord::RecordNotUnique` no concern garante que o "perdedor" da corrida encontra o record do "vencedor" e decide o que fazer baseado no status.

### Cenário: saldo insuficiente com dois withdrawals simultâneos

```
Saldo: R$ 100,00

T1:  Req A lê saldo (FOR UPDATE) → 100,00, BLOQUEIA a linha
T2:  Req B tenta FOR UPDATE      → fica ESPERANDO o lock do A
T3:  Req A subtrai 100,00        → saldo = 0, commit
T4:  Lock liberado
T5:  Req B lê saldo              → 0,00
T6:  Req B retorna 402           → insufficient_funds ✅
```

O `FOR UPDATE` no `WithdrawalService` garante serialização sem precisar de locks externos.

### Por que NÃO usar optimistic locking aqui

O `lock_version` (optimistic locking) lança `StaleObjectError` se dois processos tentam salvar a mesma linha. Isso gera retries automáticos — **perigoso** para operações financeiras onde o retry pode processar uma segunda vez.

Para débitos/créditos: **sempre use pessimistic locking (`FOR UPDATE`)**.

---

## 10. Scopes: user / group / tenant

O header `X-Idempotency-Scope` define o nível de isolamento:

```
X-Idempotency-Scope: user    →  "user_99"       (padrão)
X-Idempotency-Scope: group   →  "group_abc123"  (equipe compartilha)
X-Idempotency-Scope: tenant  →  "tenant"        (toda a empresa)
```

### Quando usar cada scope

| Scope | Caso de uso |
|-------|------------|
| `user` | Transferência pessoal, saque individual |
| `group` | Equipe financeira onde qualquer membro pode retentar a operação |
| `tenant` | Operações de onboarding, configurações globais, pagamentos da empresa |

### Exemplo: operação de grupo

```http
POST /api/v1/withdrawals
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
X-Idempotency-Scope: group
Authorization: Bearer <token-do-usuario-do-grupo>
```

Usuário A e Usuário B do mesmo grupo enviam a mesma key → um processa, o outro recebe replay. Útil quando a UI permite que qualquer membro da equipe reenvie uma operação pendente.

---

## 11. Cleanup e expiração

```ruby
# app/jobs/idempotency_cleanup_job.rb
class IdempotencyCleanupJob < ApplicationJob
  queue_as :low_priority

  def perform
    deleted = IdempotencyKey.expired.delete_all
    Rails.logger.info "[IdempotencyCleanup] Deleted #{deleted} expired keys"
  end
end
```

```ruby
# config/initializers/sidekiq_cron.rb (com sidekiq-cron)
Sidekiq::Cron::Job.create(
  name:  'Idempotency Cleanup',
  cron:  '0 3 * * *',          # 3h da manhã todo dia
  class: 'IdempotencyCleanupJob'
)
```

---

## 12. Testando com curl

### Depósito simples

#### Com Session (web client)

```bash
# Primeiro, faça login em /sessions para obter a sessão

# Primeira chamada — processa
curl -X POST http://localhost:3000/api/v1/deposits \
  -H "Content-Type: application/json" \
  -H "Cookie: session_id=SIGNED_SESSION_COOKIE" \
  -H "Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000" \
  -d '{ "deposit": { "amount": 100.00, "reference": "dep-001" } }'

# Resposta: 201 Created + transaction

# Segunda chamada (mesma key) — replay
curl -X POST http://localhost:3000/api/v1/deposits \
  -H "Content-Type: application/json" \
  -H "Cookie: session_id=SIGNED_SESSION_COOKIE" \
  -H "Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000" \
  -d '{ "deposit": { "amount": 100.00, "reference": "dep-001" } }'

# Resposta: 201 Created + MESMA transaction (não duplicou)
```

#### Com JWT (mobile/third-party)

```bash
# Primeira chamada — processa
curl -X POST http://localhost:3000/api/v1/deposits \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000" \
  -d '{ "deposit": { "amount": 100.00, "reference": "dep-001" } }'

# Resposta: 201 Created + transaction

# Segunda chamada (mesma key) — replay
curl -X POST http://localhost:3000/api/v1/deposits \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000" \
  -d '{ "deposit": { "amount": 100.00, "reference": "dep-001" } }'

# Resposta: 201 Created + MESMA transaction (não duplicou)
```

### Saque com saldo insuficiente

```bash
# Com JWT
curl -X POST http://localhost:3000/api/v1/withdrawals \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Idempotency-Key: abc-123" \
  -d '{ "withdrawal": { "amount": 99999.00 } }'

# Resposta: 402 Payment Required
# { "error": "failed", "details": ["insufficient_funds"] }

# Retry com a mesma key — replay do 402 (não tenta de novo)
curl -X POST http://localhost:3000/api/v1/withdrawals \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Idempotency-Key: abc-123" \
  -d '{ "withdrawal": { "amount": 99999.00 } }'

# Resposta: 402 (replay, não retenta o banco)
```

### Batch

```bash
# Com JWT
curl -X POST http://localhost:3000/api/v1/batch_deposits \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Idempotency-Key: batch-uuid-001" \
  -d '{
    "items": [
      { "amount": 100.00, "reference": "item-1", "item_key": "item-uuid-1" },
      { "amount": 200.00, "reference": "item-2", "item_key": "item-uuid-2" },
      { "amount":  50.00, "reference": "item-3", "item_key": "item-uuid-3" }
    ]
  }'

# Resposta: 202 Accepted
# { "batch_id": 42, "status": "pending", "total_items": 3 }

# Polling do status
curl http://localhost:3000/api/v1/batch_deposits/42 \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"

# Resposta quando concluído:
# {
#   "id": 42,
#   "status": "completed",
#   "total_items": 3,
#   "processed_items": 3,
#   "failed_items": 0,
#   "summary": { "total": 3, "succeeded": 3, "failed": 0 }
# }
```

### Conflito (double-click)

```bash
# Dois requests simultâneos com a mesma key
# Um recebe 201, o outro recebe:
# HTTP/1.1 409 Conflict
# {
#   "error": "conflict",
#   "message": "A request with this idempotency key is already being processed."
# }
```

---

## 13. Checklist de produção

### Redis
- [ ] `connect_timeout`, `read_timeout`, `write_timeout` configurados (1-2s)
- [ ] Sentinel ou Cluster para HA (se Redis cair, o fallback pro banco já está implementado)
- [ ] Persistência AOF habilitada no Redis (opcional — o banco já é a fonte da verdade)

### Banco de dados
- [ ] `UNIQUE INDEX` em `(tenant_id, scope, key)` na tabela `idempotency_keys`
- [ ] `FOR UPDATE` nos services de débito/crédito
- [ ] Connection pool adequado (Puma workers × DB connections)

### Aplicação
- [ ] `Idempotency-Key` validado como UUID no lado do servidor
- [ ] TTL configurado para o seu caso de uso (24h costuma ser suficiente)
- [ ] `IdempotencyCleanupJob` agendado no Sidekiq Cron
- [ ] Logs estruturados para monitorar hits/misses de idempotência
- [ ] Batch size limitado (`MAX_BATCH_SIZE`)

### Segurança
- [ ] `Idempotency-Key` é scoped por tenant — chave de um tenant nunca vaza para outro
- [ ] Nunca logar o body da response cacheada em plain text se contiver dados sensíveis
- [ ] Rate limit no número de keys distintas por usuário por hora (evita abuse)

---

> **Referências**
> - [Stripe: Idempotent Requests](https://stripe.com/docs/api/idempotent_requests)
> - [gem idempotent-request (Qonto)](https://github.com/qonto/idempotent-request)
> - [PostgreSQL: Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html)
