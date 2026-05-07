module TransactionTypes
  extend ActiveSupport::Concern

	included do
		before_validation :set_type, on: :create
	end

	private

	def set_type
		self.type ||= self.class.name
	end
end