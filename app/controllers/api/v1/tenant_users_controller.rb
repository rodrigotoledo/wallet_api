module Api
  module V1
    class TenantUsersController < ApplicationController
      def index
        users = User.where.not(id: current_user.id).includes(:account)

        render json: users.map { |user| UserSerializer.new(user).serializable_hash[:data][:attributes] }
      end
    end
  end
end