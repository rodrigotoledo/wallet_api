ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Helper for parsing JSONAPI responses
    def jsonapi_response(response_body = response.body)
      ActiveSupport::JSON.decode(response_body)["data"]["attributes"]
    end

    # Helper for parsing JSONAPI collection responses
    def jsonapi_collection(response_body = response.body)
      ActiveSupport::JSON.decode(response_body)["data"].map { |item| item["attributes"] }
    end
  end
end
