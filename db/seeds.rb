# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Create a demo tenant for transfers
demo_tenant = Tenant.find_or_create_by!(subdomain: "demo") do |tenant|
  tenant.name = "Demo Bank"
end

# Create users with accounts in the demo tenant
alice = User.find_or_create_by!(tenant: demo_tenant, email_address: "alice@demo.com") do |user|
  user.password = "password123"
  user.tenant = demo_tenant
end

bob = User.find_or_create_by!(tenant: demo_tenant, email_address: "bob@demo.com") do |user|
  user.password = "password123"
  user.tenant = demo_tenant
end

charlie = User.find_or_create_by!(tenant: demo_tenant, email_address: "charlie@demo.com") do |user|
  user.password = "password123"
  user.tenant = demo_tenant
end

# Create accounts for each user in the demo tenant
alice_account = Account.find_or_create_by!(tenant: demo_tenant, user: alice, currency: "USD") do |account|
  account.balance = 1000.00
end

bob_account = Account.find_or_create_by!(tenant: demo_tenant, user: bob, currency: "USD") do |account|
  account.balance = 500.00
end

charlie_account = Account.find_or_create_by!(tenant: demo_tenant, user: charlie, currency: "USD") do |account|
  account.balance = 200.00
end

puts "Created demo tenant '#{demo_tenant.name}' with users: Alice ($#{alice_account.balance}), Bob ($#{bob_account.balance}), Charlie ($#{charlie_account.balance})"

Tenant.all.each do |tenant|
  3.times do |i|
    user = User.find_or_create_by!(tenant: tenant, email_address: "user#{i + 1}@#{tenant.subdomain}.com") do |user|
      user.password = "password123"
    end

    Account.find_or_create_by!(tenant: tenant, user: user, currency: "USD") do |account|
      account.balance = 100.00
    end 
  end
end