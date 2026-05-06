class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :type
      t.decimal :amount
      t.string :currency
      t.string :status
      t.string :reference
      t.jsonb :metadata

      t.timestamps
    end
    add_index :transactions, [:tenant_id, :account_id]
    add_index :transactions, :status
  end
end
