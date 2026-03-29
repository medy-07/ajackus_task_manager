class ApplicationController < ActionController::API
  include RequestLogging

  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from Task::InvalidTransitionError, with: :conflict

  private

  def not_found
    render json: {
      error: { code: "not_found", message: "Resource not found" }
    }, status: :not_found
  end

  def conflict(exception)
    render json: {
      error: { code: "invalid_transition", message: exception.message }
    }, status: :conflict
  end
end
