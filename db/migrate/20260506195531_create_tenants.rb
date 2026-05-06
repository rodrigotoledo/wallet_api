class CreateTenants < ActiveRecord::Migration[8.1]
  def change
    create_table :tenants do |t|
      t.string :name
      t.string :subdomain
      t.string :status

      t.timestamps
    end
    add_index :tenants, :subdomain, unique: true
  end
end
