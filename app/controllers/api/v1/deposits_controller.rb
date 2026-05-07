module Api
  module V1
    class DepositsController < ApplicationController
      include Idempotent

      def create
        result = DepositService.call(
          user:    current_user,
          tenant:  current_tenant,
          amount:  deposit_params[:amount],
          currency: deposit_params[:currency] || 'USD',
          reference: deposit_params[:reference]
        )

        if result.success?
          render json: TransactionSerializer.new(result.transaction),
                 status: :created
        else
          render json: { error: 'unprocessable_entity', details: result.errors },
                 status: :unprocessable_entity
        end
      end

      private

      def deposit_params
        params.require(:deposit).permit(:amount, :currency, :reference)
      end
    end
  end
end
