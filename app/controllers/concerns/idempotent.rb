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
    # First action with Redis (best-effort)
    if (cached = read_from_redis)
      @idempotency_replayed = true
      render json: cached[:body], status: cached[:status]
      return
    end

    # 2. Database (source of truth)
    record = find_or_initialize_idempotency_record
    @idempotency_record = record

    case record.status
    when 'completed'
      write_to_redis(record)           # backfill Redis
      @idempotency_replayed = true
      render json: record.response_body, status: record.response_status

    when 'processing'
      # Another instance is processing — return 409
      render json: {
        error: 'conflict',
        message: 'A request with this idempotency key is already being processed.',
        idempotency_key: idempotency_key
      }, status: :conflict

    when 'failed'
      # Failed before — allow retry, reset to processing
      record.update!(
        status:    :processing,
        locked_at: Time.current
      )
    end
  end

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
      # 5xx error — mark as failed to allow retry
      @idempotency_record.update!(
        status:    :failed,
        locked_at: nil
      )
    end
  end

  def find_or_initialize_idempotency_record
    IdempotencyKey.transaction do
      record = IdempotencyKey.lock.find_by(
        tenant: current_tenant,
        scope:  idempotency_scope_key,
        key:    idempotency_key
      )

      return record if record.present?

      IdempotencyKey.create!(
        tenant:         current_tenant,
        scope:          idempotency_scope_key,
        key:            idempotency_key,
        user:           current_user,
        status:         :processing,
        locked_at:      Time.current,
        expires_at:     IDEMPOTENCY_TTL.from_now,
        request_path:   request.path,
        request_method: request.method
      )
    end
  end

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
    else               "user_#{current_user.id}"
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