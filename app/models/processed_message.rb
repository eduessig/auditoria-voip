class ProcessedMessage < ApplicationRecord
  belongs_to :call, inverse_of: :processed_messages

  validates :message_id, presence: true, uniqueness: true
  validates :processed_at, presence: true
end
