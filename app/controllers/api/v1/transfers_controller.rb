module Api
  module V1
    class TransfersController < ApplicationController
      include Idempotent

      def create
        result = TransferService.call(
          sender:   current_user,
          recipient: find_recipient,
          tenant:   current_tenant,
          amount:   transfer_params[:amount],
          currency: transfer_params[:currency] || 'USD',
          reference: transfer_params[:reference]
        )

        if result.success?
          render json: TransferSerializer.new(result.transaction),
                 status: :created
        else
          render json: { error: 'unprocessable_entity', details: result.errors },
                 status: :unprocessable_entity
        end
      end

      private

      def transfer_params
        params.require(:transfer).permit(:recipient_id, :amount, :currency, :reference)
      end

      def find_recipient
        User.find_by!(id: transfer_params[:recipient_id])
      rescue ActiveRecord::RecordNotFound
        raise ActionController::BadRequest, "Recipient not found"
      end
    end
  end
end
