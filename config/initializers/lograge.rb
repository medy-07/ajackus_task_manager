Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new

  config.lograge.custom_options = lambda do |event|
    {
      request_id: event.payload[:request_id],
      remote_ip: event.payload[:remote_ip],
      idempotency_key: event.payload[:idempotency_key]
    }.compact
  end

  config.lograge.custom_payload do |controller|
    {
      request_id: controller.request.request_id,
      remote_ip: controller.request.remote_ip,
      idempotency_key: controller.request.headers["Idempotency-Key"]
    }
  end
end
