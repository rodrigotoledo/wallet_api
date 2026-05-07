module Api
  module V1
    class TransactionsController < ApplicationController
      def index
        # acts_as_tenant já filtra automaticamente
        transactions = Transaction
          .where(user: current_user)
          .order(created_at: :desc)
          .limit(params[:limit] || 50)

        render json: TransactionSerializer.new(transactions).serializable_hash
      end
    end
  end
end
