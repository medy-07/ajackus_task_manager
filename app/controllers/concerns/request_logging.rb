module RequestLogging
  extend ActiveSupport::Concern

  included do
    before_action :log_request_start
    after_action :log_request_end
  end

  private

  def log_request_start
    Rails.logger.tagged(request_tag) do
      Rails.logger.info("Started #{request.method} #{request.path}")
    end
  end

  def log_request_end
    Rails.logger.tagged(request_tag) do
      Rails.logger.info("Completed #{response.status}")
    end
  end

  def request_tag
    "req:#{request.request_id}"
  end
end
