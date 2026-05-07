module Api
  module V1
    class WithdrawalsController < ApplicationController
      include Idempotent

      def create
        result = WithdrawalService.call(
          user:    current_user,
          tenant:  current_tenant,
          amount:  withdrawal_params[:amount],
          currency: withdrawal_params[:currency] || 'USD',
          reference: withdrawal_params[:reference]
        )

        if result.success?
          render json: TransactionSerializer.new(result.transaction),
                 status: :created
        else
          status = result.errors.include?('insufficient_funds') ? :payment_required : :unprocessable_entity
          render json: { error: 'failed', details: result.errors },
                 status: status
        end
      end

      private

      def withdrawal_params
        params.require(:withdrawal).permit(:amount, :currency, :reference)
      end
    end
  end
end
