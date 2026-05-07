module Api
  module V1
    class BatchDepositsController < ApplicationController
      include Idempotent

      MAX_BATCH_SIZE = 100

      def create
        items = batch_params[:items]

        if items.size > MAX_BATCH_SIZE
          return render json: {
            error: 'too_many_items',
            message: "Maximum #{MAX_BATCH_SIZE} items per batch"
          }, status: :unprocessable_entity
        end

        batch = BatchOperation.create!(
          tenant:         current_tenant,
          user:           current_user,
          operation_type: 'batch_deposit',
          status:         'pending',
          total_items:    items.size,
          items:          items
        )

        render json: {
          batch_id:    batch.id,
          status:      batch.status,
          total_items: batch.total_items,
          message:     'Batch accepted. /api/v1/batch_deposits/:id for status.'
        }, status: :accepted
      rescue ActiveRecord::RecordInvalid => e
        head :unprocessable_entity
      end

      def show
        batch = BatchOperation.find_by!(
          id:     params[:id],
          tenant: current_tenant
        )

        render json: batch.as_json(
          only: %i[
            id status total_items processed_items failed_items
            results summary created_at updated_at
          ]
        )
      end

      private

      def batch_params
        params.permit(items: [:amount, :currency, :reference, :item_key])
      end
    end
  end
end
