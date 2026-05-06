class CreateBatchOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :batch_operations do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :operation_type
      t.string :status
      t.integer :total_items
      t.integer :processed_items
      t.integer :failed_items
      t.jsonb :items
      t.jsonb :results
      t.jsonb :summary

      t.timestamps
    end
  end
end
