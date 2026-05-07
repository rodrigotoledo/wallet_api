class Transfer < Transaction
  validates :recipient_account, :recipient_user, presence: true
end
