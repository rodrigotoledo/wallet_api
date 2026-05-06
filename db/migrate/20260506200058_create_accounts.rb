class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :currency, null: false, default: 'USD'
      t.decimal :balance, null: false, default: 0, precision: 15, scale: 2
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end
    add_index :accounts, [:tenant_id, :user_id, :currency], unique: true
  end
end
