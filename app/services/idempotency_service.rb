class IdempotencyService
  def initialize(idempotency_key, task_params)
    @idempotency_key = idempotency_key
    @task_params = task_params
  end

  def execute
    existing = IdempotencyKey.find_by(key: @idempotency_key)
    return handle_existing(existing) if existing

    create_new_task
  end

  private

  def handle_existing(idem_record)
    task = idem_record.task

    if task.terminal?
      Rails.logger.info("[Idempotency] Returning cached response for key=#{@idempotency_key} task=#{task.ticket_number}")
      { status: idem_record.response_code, body: idem_record.response_body }
    else
      Rails.logger.info("[Idempotency] Duplicate request for in-progress task key=#{@idempotency_key} task=#{task.ticket_number}")
      {
        status: 409,
        body: { error: "Request is already being processed", task_id: task.id }
      }
    end
  end

  def create_new_task
    task = Task.new(
      @task_params.merge(idempotency_key: @idempotency_key)
    )

    unless task.valid?
      return { status: 400, body: { errors: task.errors.full_messages } }
    end

    ActiveRecord::Base.transaction do
      lock_key = Zlib.crc32(@idempotency_key)
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{lock_key})")

      if (existing = IdempotencyKey.find_by(key: @idempotency_key))
        return handle_existing(existing)
      end

      task.save!

      response_body = task_response(task)

      IdempotencyKey.create!(
        key: @idempotency_key,
        task: task,
        response_code: 202,
        response_body: response_body
      )

      TaskProcessorJob.perform_later(task.id)

      Rails.logger.info("[Idempotency] Created task=#{task.ticket_number} key=#{@idempotency_key}, job enqueued")

      { status: 202, body: response_body }
    end
  end

  def task_response(task)
    {
      id: task.id,
      ticket_number: task.ticket_number,
      title: task.title,
      status: task.status,
      priority: task.priority,
      created_at: task.created_at
    }
  end
end
