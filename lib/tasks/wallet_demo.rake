require "json"
require "net/http"
require "securerandom"
require "uri"

namespace :wallet do
  desc "Run an authenticated wallet API demo through the real HTTP endpoints"
  task demo: :environment do
    base_url = URI(ENV.fetch("BASE_URL", "http://localhost:3000"))
    run_id = SecureRandom.uuid

    tenant = Tenant.find_or_create_by!(subdomain: "demo") do |record|
      record.name = "Demo Tenant"
      record.status = "active"
    end

    user = User.find_or_initialize_by(tenant: tenant, email_address: "demo@example.com")
    user.password = "password" if user.new_record?
    user.role ||= :member
    user.save!

    account = Account.find_or_create_by!(tenant: tenant, user: user, currency: "USD")
    account.update!(balance: 100.to_d) if account.balance.zero?

    print_step "Using API at #{base_url}"
    print_step "Signing in through POST /session as #{user.email_address}"
    login_response = http_post_json(
      base_url,
      "/session",
      {
        email_address: user.email_address,
        password: "password"
      }
    )
    print_response(login_response)

    token = parse_json(login_response)["token"]

    unless token
      abort <<~MESSAGE
        Login did not return a JWT token.

        HTTP #{login_response.code}
        Body: #{login_response.body}

        Make sure #{base_url} is running this Rails app and was restarted after the JWT login changes.
      MESSAGE
    end

    print_step "Authenticated deposit through POST /api/v1/deposits"
    deposit_response = http_post_json(
      base_url,
      "/api/v1/deposits",
      {
        deposit: {
          amount: "25.00",
          currency: "USD",
          reference: "rake-demo-deposit"
        }
      },
      {
        "Authorization" => "Bearer #{token}",
        "Idempotency-Key" => "rake-demo-deposit-#{run_id}"
      }
    )
    print_response(deposit_response)

    print_step "Authenticated withdrawal through POST /api/v1/withdrawals"
    withdrawal_response = http_post_json(
      base_url,
      "/api/v1/withdrawals",
      {
        withdrawal: {
          amount: "10.00",
          currency: "USD",
          reference: "rake-demo-withdrawal"
        }
      },
      {
        "Authorization" => "Bearer #{token}",
        "Idempotency-Key" => "rake-demo-withdrawal-#{run_id}"
      }
    )
    print_response(withdrawal_response)

    print_step "Authenticated batch deposit through POST /api/v1/batch_deposits"
    batch_response = http_post_json(
      base_url,
      "/api/v1/batch_deposits",
      {
        items: [
          {
            amount: "5.00",
            currency: "USD",
            reference: "batch-item-1",
            item_key: "rake-demo-item-1-#{run_id}"
          },
          {
            amount: "7.50",
            currency: "USD",
            reference: "batch-item-2",
            item_key: "rake-demo-item-2-#{run_id}"
          }
        ]
      },
      {
        "Authorization" => "Bearer #{token}",
        "Idempotency-Key" => "rake-demo-batch-#{run_id}"
      }
    )
    print_response(batch_response)

    batch_id = parse_json(batch_response).fetch("batch_id")

    if ENV["PROCESS_BATCH_INLINE"] == "1"
      print_step "Processing BatchDepositJob locally for batch #{batch_id}"
      BatchDepositJob.new.perform(batch_id)
    else
      puts "\nBatch processing is asynchronous. Run Sidekiq in another terminal:"
      puts "bundle exec sidekiq -C config/sidekiq.yml"
      puts "Or rerun this task with PROCESS_BATCH_INLINE=1 to process the created batch locally."
    end

    print_step "Polling batch result through GET /api/v1/batch_deposits/#{batch_id}"
    batch_result = poll_batch_result(base_url, batch_id, token)
    print_response(batch_result)

    account.reload
    puts "\nFinal #{account.currency} balance: #{account.balance}"
  rescue Errno::ECONNREFUSED
    abort "Could not connect to #{base_url}. Start the server with: bin/rails server"
  end

  def http_post_json(base_url, path, payload, headers = {})
    request = Net::HTTP::Post.new(path)
    request.body = JSON.generate(payload)
    request["Accept"] = "application/json"
    request["Content-Type"] = "application/json"
    headers.each { |key, value| request[key] = value }

    perform_request(base_url, request)
  end

  def http_get_json(base_url, path, headers = {})
    request = Net::HTTP::Get.new(path)
    request["Accept"] = "application/json"
    headers.each { |key, value| request[key] = value }

    perform_request(base_url, request)
  end

  def perform_request(base_url, request)
    Net::HTTP.start(base_url.host, base_url.port, use_ssl: base_url.scheme == "https") do |http|
      http.request(request)
    end
  end

  def poll_batch_result(base_url, batch_id, token)
    response = nil

    10.times do
      response = http_get_json(
        base_url,
        "/api/v1/batch_deposits/#{batch_id}",
        { "Authorization" => "Bearer #{token}" }
      )
      body = parse_json(response)
      break if %w[completed failed partial].include?(body["status"])

      sleep 1
    end

    response
  end

  def print_step(message)
    puts "\n== #{message}"
  end

  def print_response(response)
    puts "HTTP #{response.code}"

    body = response.body
    return if body.blank?

    puts JSON.pretty_generate(JSON.parse(body))
  rescue JSON::ParserError
    puts body
  end

  def parse_json(response)
    JSON.parse(response.body)
  end
end
