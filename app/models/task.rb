class Task < ApplicationRecord
  class InvalidTransitionError < StandardError; end

  STATUSES = %w[pending processing completed failed cancelled].freeze
  PRIORITIES = %w[low medium high critical].freeze
  TERMINAL_STATUSES = %w[completed cancelled].freeze
  TICKET_PREFIX = "QCK".freeze

  VALID_TRANSITIONS = {
    "pending"    => %w[processing cancelled],
    "processing" => %w[completed failed cancelled],
    "failed"     => %w[processing],
    "completed"  => [],
    "cancelled"  => []
  }.freeze

  has_one :idempotency_key_record, class_name: "IdempotencyKey", foreign_key: :task_id, dependent: :destroy

  validates :title, presence: true
  validates :idempotency_key, presence: true, uniqueness: true
  validates :ticket_number, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: PRIORITIES }

  scope :retryable, -> { where(status: "failed").where("attempts < max_attempts") }
  scope :cancellable, -> { where(status: %w[pending processing]) }
  scope :by_status, ->(s) { where(status: s) }

  before_validation :assign_ticket_number, on: :create

  def mark_processing!
    ensure_transition_allowed!("processing")
    validate_retry_budget! if status == "failed"

    self.status = "processing"
    self.started_at = Time.current
    self.attempts += 1
    save!
  end

  def mark_completed!(result_data)
    ensure_transition_allowed!("completed")

    self.status = "completed"
    self.completed_at = Time.current
    self.result = result_data
    save!
  end

  def mark_failed!(error_msg)
    ensure_transition_allowed!("failed")

    self.status = "failed"
    self.error_message = error_msg
    save!
  end

  def cancel!
    ensure_transition_allowed!("cancelled")

    self.status = "cancelled"
    self.cancelled_at = Time.current
    save!
  end

  def retryable?
    status == "failed" && attempts < max_attempts
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  private

  def assign_ticket_number
    return if ticket_number.present?

    seq = self.class.connection.execute("SELECT nextval('task_ticket_number_seq')").first["nextval"]
    self.ticket_number = "#{TICKET_PREFIX}-#{seq}"
  end

  def ensure_transition_allowed!(target)
    allowed = VALID_TRANSITIONS.fetch(status, [])
    return if allowed.include?(target)

    raise InvalidTransitionError,
      "Cannot transition from '#{status}' to '#{target}'"
  end

  def validate_retry_budget!
    return if attempts < max_attempts

    raise InvalidTransitionError,
      "Retry budget exhausted (#{attempts}/#{max_attempts})"
  end
end
