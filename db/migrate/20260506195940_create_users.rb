class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :group_key
      t.string :role, null: false, default: "member"

      t.timestamps
    end
    add_index :users, [:tenant_id, :email_address], unique: true
  end
end
