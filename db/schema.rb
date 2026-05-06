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

ActiveRecord::Schema[8.1].define(version: 2026_05_06_200512) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.decimal "balance"
    t.datetime "created_at", null: false
    t.string "currency"
    t.integer "lock_version"
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["tenant_id", "user_id", "currency"], name: "index_accounts_on_tenant_id_and_user_id_and_currency", unique: true
    t.index ["tenant_id"], name: "index_accounts_on_tenant_id"
    t.index ["user_id"], name: "index_accounts_on_user_id"
  end

  create_table "batch_operations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "failed_items"
    t.jsonb "items"
    t.string "operation_type"
    t.integer "processed_items"
    t.jsonb "results"
    t.string "status"
    t.jsonb "summary"
    t.bigint "tenant_id", null: false
    t.integer "total_items"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["tenant_id"], name: "index_batch_operations_on_tenant_id"
    t.index ["user_id"], name: "index_batch_operations_on_user_id"
  end

  create_table "idempotency_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "key"
    t.datetime "locked_at"
    t.string "request_method"
    t.string "request_path"
    t.jsonb "response_body"
    t.integer "response_status"
    t.string "scope"
    t.integer "status"
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
    t.string "name"
    t.string "status"
    t.string "subdomain"
    t.datetime "updated_at", null: false
    t.index ["subdomain"], name: "index_tenants_on_subdomain", unique: true
  end

  create_table "transactions", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.decimal "amount"
    t.datetime "created_at", null: false
    t.string "currency"
    t.jsonb "metadata"
    t.string "reference"
    t.string "status"
    t.bigint "tenant_id", null: false
    t.string "type"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["status"], name: "index_transactions_on_status"
    t.index ["tenant_id", "account_id"], name: "index_transactions_on_tenant_id_and_account_id"
    t.index ["tenant_id"], name: "index_transactions_on_tenant_id"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "accounts", "tenants"
  add_foreign_key "accounts", "users"
  add_foreign_key "batch_operations", "tenants"
  add_foreign_key "batch_operations", "users"
  add_foreign_key "idempotency_keys", "tenants"
  add_foreign_key "idempotency_keys", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "transactions", "accounts"
  add_foreign_key "transactions", "tenants"
  add_foreign_key "transactions", "users"
end
