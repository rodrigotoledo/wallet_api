module Api
  module V1
    class TransactionsController < ApplicationController
      def index
        transactions = current_user.transactions
          .order(created_at: :desc)
          .limit(params[:limit] || 50)
        render json: TransactionSerializer.new(transactions)
      end
    end
  end
end
