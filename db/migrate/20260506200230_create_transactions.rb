class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :type, null: false
      t.decimal :amount, null: false, precision: 15, scale: 2
      t.string :currency, null: false, default: 'USD'
      t.integer :status, null: false, default: 0
      t.string :reference
      t.jsonb :metadata, default: {}

      t.timestamps
    end
    add_index :transactions, [ :tenant_id, :account_id ]
    add_index :transactions, :status
  end
end
