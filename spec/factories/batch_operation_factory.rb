FactoryBot.define do
  factory :batch_operation do
    tenant
    user
    operation_type { "deposit" }
    status { "pending" }
    total_items { 1 }
    processed_items { 0 }
    failed_items { 0 }
    items { [] }
    results { [] }
    summary { {} }
  end
end