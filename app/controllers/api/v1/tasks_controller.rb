module Api
  module V1
    class TasksController < ApplicationController
      before_action :require_idempotency_key, only: :create

      def index
        tasks = Task.all
        tasks = tasks.by_status(params[:status]) if params[:status].present?
        tasks = tasks.order(created_at: :desc)

        render json: tasks.map { |t| task_json(t) }
      end

      def show
        task = Task.find(params[:id])
        render json: task_json(task)
      end

      def create
        service = IdempotencyService.new(idempotency_key, task_params)
        result = service.execute

        render json: result[:body], status: result[:status]
      end

      def cancel
        task = Task.find(params[:id])
        task.cancel!

        render json: task_json(task)
      end

      private

      def task_params
        params.require(:task).permit(:title, :description, :priority)
      end

      def idempotency_key
        request.headers["Idempotency-Key"]
      end

      def require_idempotency_key
        return if idempotency_key.present?

        render json: {
          error: { code: "missing_idempotency_key", message: "Idempotency-Key header is required" }
        }, status: :bad_request
      end

      def task_json(task)
        {
          id: task.id,
          ticket_number: task.ticket_number,
          title: task.title,
          description: task.description,
          priority: task.priority,
          status: task.status,
          attempts: task.attempts,
          max_attempts: task.max_attempts,
          error_message: task.error_message,
          result: task.result,
          started_at: task.started_at,
          completed_at: task.completed_at,
          cancelled_at: task.cancelled_at,
          created_at: task.created_at,
          updated_at: task.updated_at
        }
      end
    end
  end
end
