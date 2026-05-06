class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :idempotency_keys do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :scope, null: false
      t.string :key, null: false
      t.string :request_path, null: false
      t.string :request_method, null: false, default: 'POST'
      t.integer :status, null: false, default: 0
      t.integer :response_status
      t.jsonb :response_body
      t.datetime :locked_at
      t.datetime :expires_at, null: false

      t.timestamps
    end
    add_index :idempotency_keys,
              [:tenant_id, :scope, :key],
              unique: true,
              name: 'idx_idempotency_unique'

    add_index :idempotency_keys, :expires_at
    add_index :idempotency_keys, :status
  end
end
