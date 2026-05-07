class AddTransferFieldsToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :recipient_account_id, :bigint
    add_column :transactions, :recipient_user_id, :bigint

    add_index :transactions, :recipient_account_id
    add_index :transactions, :recipient_user_id

    add_foreign_key :transactions, :accounts, column: :recipient_account_id
    add_foreign_key :transactions, :users, column: :recipient_user_id
  end
end
