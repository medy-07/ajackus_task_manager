class IdempotencyKey < ApplicationRecord
  belongs_to :task

  validates :key, presence: true, uniqueness: true
end
