class BatchOperationSerializer
  include JSONAPI::Serializer

  attributes :id, :status, :total_items, :processed_items, :failed_items,
             :results, :summary, :created_at, :updated_at
end
