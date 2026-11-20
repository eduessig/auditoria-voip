class Call < ApplicationRecord
  STATUSES = %w[answered missed rejected].freeze

  has_many :processed_messages, inverse_of: :call

  validates :call_id, :caller, :callee, :started_at, :ended_at, presence: true
  validates :call_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :duration_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :times_are_ordered
  validate :answer_matches_status

  private

  def times_are_ordered
    errors.add(:ended_at, "must be on or after started_at") if started_at && ended_at && ended_at < started_at
    return unless answered_at

    errors.add(:answered_at, "must be on or after started_at") if started_at && answered_at < started_at
    errors.add(:answered_at, "must be on or before ended_at") if ended_at && answered_at > ended_at
  end

  def answer_matches_status
    if status == "answered"
      errors.add(:answered_at, "is required for answered calls") if answered_at.nil?
    elsif %w[missed rejected].include?(status)
      errors.add(:answered_at, "must be absent for unanswered calls") if answered_at.present?
      errors.add(:duration_seconds, "must be zero for unanswered calls") unless duration_seconds == 0
    end
  end
end
