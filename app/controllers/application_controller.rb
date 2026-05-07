class ApplicationController < ActionController::Base
  skip_forgery_protection

  include Authentication
end
