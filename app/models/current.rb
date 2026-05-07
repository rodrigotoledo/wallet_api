class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :tenant

  def user
    session&.user || super
  end
end
