class CreateBatchOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :batch_operations do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :operation_type, null: false
      t.string :status, null: false, default: 'pending'
      t.integer :total_items, null: false, default: 0
      t.integer :processed_items, null: false, default: 0
      t.integer :failed_items, null: false, default: 0
      t.jsonb :items, null: false, default: []
      t.jsonb :results, null: false, default: []
      t.jsonb :summary, null: false, default: {}

      t.timestamps
    end
  end
end
