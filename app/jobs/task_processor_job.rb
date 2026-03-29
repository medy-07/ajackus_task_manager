class TaskProcessorJob < ApplicationJob
  queue_as :task_processing

  STALE_OBJECT_MAX_RETRIES = 3
  BASE_BACKOFF_SECONDS = 5

  def perform(task_id, stale_retries: 0)
    task = Task.find_by(id: task_id)
    unless task
      Rails.logger.warn("[TaskProcessorJob] Task #{task_id} not found, skipping")
      return
    end

    if task.terminal?
      Rails.logger.info("[TaskProcessorJob] Task #{task.ticket_number} is #{task.status}, skipping")
      return
    end

    begin
      task.mark_processing!
      Rails.logger.info("[TaskProcessorJob] Task #{task.ticket_number} moved to processing (attempt #{task.attempts})")
    rescue ActiveRecord::StaleObjectError
      if stale_retries < STALE_OBJECT_MAX_RETRIES
        Rails.logger.warn("[TaskProcessorJob] StaleObjectError for #{task.ticket_number}, retrying (#{stale_retries + 1}/#{STALE_OBJECT_MAX_RETRIES})")
        self.class.perform_now(task_id, stale_retries: stale_retries + 1)
        return
      else
        Rails.logger.error("[TaskProcessorJob] StaleObjectError exhausted for #{task.ticket_number}")
        return
      end
    end

    begin
      service = TaskProcessorService.new(task)
      result = service.call

      task.reload
      task.mark_completed!(result)
      Rails.logger.info("[TaskProcessorJob] Task #{task.ticket_number} completed successfully")
    rescue TransientError => e
      handle_transient_failure(task, e)
    rescue PermanentError => e
      handle_permanent_failure(task, e)
    rescue DataCorruptionError => e
      handle_permanent_failure(task, e)
    end
  end

  private

  def handle_transient_failure(task, error)
    task.reload
    task.mark_failed!(error.message)
    Rails.logger.warn("[TaskProcessorJob] Task #{task.ticket_number} failed (transient): #{error.message}")

    if task.retryable?
      backoff = BASE_BACKOFF_SECONDS * (2**task.attempts)
      self.class.set(wait: backoff.seconds).perform_later(task.id)
      Rails.logger.info("[TaskProcessorJob] Task #{task.ticket_number} scheduled for retry in #{backoff}s (attempt #{task.attempts}/#{task.max_attempts})")
    else
      Rails.logger.error("[TaskProcessorJob] Task #{task.ticket_number} exhausted all retries")
    end
  end

  def handle_permanent_failure(task, error)
    task.reload
    task.mark_failed!(error.message)
    Rails.logger.error("[TaskProcessorJob] Task #{task.ticket_number} failed (permanent): #{error.message}")
  end
end
