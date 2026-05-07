module Api
  module V1
    class ProfilesController < ApplicationController
      def show
        render json: {
          user: UserSerializer.new(current_user).serializable_hash[:data][:attributes],
          tenant: TenantSerializer.new(current_tenant).serializable_hash[:data][:attributes]
        }
      end
    end
  end
end
