# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_07_150822) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.decimal "balance", precision: 15, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["tenant_id", "user_id", "currency"], name: "index_accounts_on_tenant_id_and_user_id_and_currency", unique: true
    t.index ["tenant_id"], name: "index_accounts_on_tenant_id"
    t.index ["user_id"], name: "index_accounts_on_user_id"
  end

  create_table "batch_operations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "failed_items", default: 0, null: false
    t.jsonb "items", default: [], null: false
    t.string "operation_type", null: false
    t.integer "processed_items", default: 0, null: false
    t.jsonb "results", default: [], null: false
    t.string "status", default: "pending", null: false
    t.jsonb "summary", default: {}, null: false
    t.bigint "tenant_id", null: false
    t.integer "total_items", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["tenant_id"], name: "index_batch_operations_on_tenant_id"
    t.index ["user_id"], name: "index_batch_operations_on_user_id"
  end

  create_table "idempotency_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "locked_at"
    t.string "request_method", default: "POST", null: false
    t.string "request_path", null: false
    t.jsonb "response_body"
    t.integer "response_status"
    t.string "scope", null: false
    t.integer "status", default: 0, null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_idempotency_keys_on_expires_at"
    t.index ["status"], name: "index_idempotency_keys_on_status"
    t.index ["tenant_id", "scope", "key"], name: "idx_idempotency_unique", unique: true
    t.index ["tenant_id"], name: "index_idempotency_keys_on_tenant_id"
    t.index ["user_id"], name: "index_idempotency_keys_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "status", default: "active", null: false
    t.string "subdomain", null: false
    t.datetime "updated_at", null: false
    t.index ["subdomain"], name: "index_tenants_on_subdomain", unique: true
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.jsonb "metadata", default: {}
    t.bigint "recipient_account_id"
    t.bigint "recipient_user_id"
    t.string "reference"
    t.integer "status", default: 0, null: false
    t.bigint "tenant_id", null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["recipient_account_id"], name: "index_transactions_on_recipient_account_id"
    t.index ["recipient_user_id"], name: "index_transactions_on_recipient_user_id"
    t.index ["status"], name: "index_transactions_on_status"
    t.index ["tenant_id", "account_id"], name: "index_transactions_on_tenant_id_and_account_id"
    t.index ["tenant_id"], name: "index_transactions_on_tenant_id"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "group_key"
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "email_address"], name: "index_users_on_tenant_id_and_email_address", unique: true
    t.index ["tenant_id"], name: "index_users_on_tenant_id"
  end

  add_foreign_key "accounts", "tenants"
  add_foreign_key "accounts", "users"
  add_foreign_key "batch_operations", "tenants"
  add_foreign_key "batch_operations", "users"
  add_foreign_key "idempotency_keys", "tenants"
  add_foreign_key "idempotency_keys", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "accounts", column: "recipient_account_id"
  add_foreign_key "transactions", "tenants"
  add_foreign_key "transactions", "users"
  add_foreign_key "transactions", "users", column: "recipient_user_id"
  add_foreign_key "users", "tenants"
end
