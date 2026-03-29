class TaskProcessorService
  SIMULATION_MODES = %i[success transient_failure permanent_failure data_corruption slow_processing].freeze

  def initialize(task, simulate: :success)
    @task = task
    @simulate = simulate
  end

  def call
    case @simulate
    when :transient_failure
      raise TransientError, "Downstream transient failure: connection timeout"
    when :permanent_failure
      raise PermanentError, "Downstream permanent failure: invalid resource"
    when :data_corruption
      raise DataCorruptionError, "Data integrity check failed: checksum mismatch"
    when :slow_processing
      sleep(0.1)
    end

    {
      task_id: @task.id,
      processed_at: Time.current.iso8601,
      message: "Task '#{@task.title}' processed successfully"
    }
  end
end
