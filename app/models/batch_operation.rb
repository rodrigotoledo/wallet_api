class BatchOperation < ApplicationRecord
  acts_as_tenant :tenant
  belongs_to :tenant
  belongs_to :user

  after_create_commit :enqueue_processing

  private

  def enqueue_processing
    BatchDepositJob.perform_async(id)
  end
end
