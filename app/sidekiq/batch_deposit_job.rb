class BatchDepositJob
  include Sidekiq::Job

  sidekiq_options retry: 5, dead: true

  def perform(batch_id)
    batch = BatchOperation.find(batch_id)
    batch.update!(status: :processing)

    results      = []
    failed_count = 0

    batch.items.each_with_index do |item, index|
      result = process_item(batch, item, index)
      results << result
      failed_count += 1 unless result[:success]

      # can update to polling, so its another choice
      batch.update!(
        processed_items: index + 1,
        results:         results
      )
    end

    final_status = determine_final_status(results, batch.total_items, failed_count)

    batch.update!(
      status:        final_status,
      failed_items:  failed_count,
      results:       results,
      summary: {
        total:         batch.total_items,
        succeeded:     batch.total_items - failed_count,
        failed:        failed_count,
        completed_at:  Time.current.iso8601
      }
    )
  end

  private

  def process_item(batch, item, index)
    item_key     = item["item_key"] || "#{batch.id}-item-#{index}"
    idempotency_record_key = "batch_item:#{batch.tenant_id}:#{item_key}"

    existing = Rails.cache.read(idempotency_record_key)
    return existing if existing

    result = DepositService.call(
      user:      batch.user,
      tenant:    batch.tenant,
      amount:    item["amount"],
      currency:  item["currency"] || "USD",
      reference: item["reference"]
    )

    response = if result.success?
      {
        index:          index,
        item_key:       item_key,
        success:        true,
        transaction_id: result.transaction.id,
        amount:         result.transaction.amount
      }
    else
      {
        index:    index,
        item_key: item_key,
        success:  false,
        errors:   result.errors
      }
    end

    Rails.cache.write(idempotency_record_key, response, expires_in: 24.hours)
    response
  rescue => e
    Rails.logger.error "[BatchDeposit] Item #{index} failed: #{e.message}"
    { index: index, item_key: item_key, success: false, errors: [ e.message ] }
  end

  def determine_final_status(results, total, failed_count)
    if failed_count == 0           then :completed
    elsif failed_count == total    then :failed
    else                                :partial
    end
  end
end
