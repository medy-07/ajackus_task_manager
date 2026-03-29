require 'rails_helper'

RSpec.describe "Full workflow integration", type: :request do
  include ActiveJob::TestHelper

  describe "happy path: create -> process -> complete" do
    it "creates a task, processes it via background job, and completes" do
      key = SecureRandom.uuid

      post "/api/v1/tasks",
        params: { task: { title: "Integration test", priority: "high" } }.to_json,
        headers: { "Idempotency-Key" => key, "Content-Type" => "application/json" }

      expect(response).to have_http_status(202)
      body = JSON.parse(response.body)
      task_id = body["id"]

      get "/api/v1/tasks/#{task_id}", as: :json
      expect(JSON.parse(response.body)["status"]).to eq("pending")

      perform_enqueued_jobs

      get "/api/v1/tasks/#{task_id}", as: :json
      result = JSON.parse(response.body)
      expect(result["status"]).to eq("completed")
      expect(result["result"]).to be_present
      expect(result["completed_at"]).to be_present
      expect(result["ticket_number"]).to match(/\AQCK-\d+\z/)
    end
  end

  describe "failure path: create -> fail -> retry -> succeed" do
    it "retries on transient failure and eventually succeeds" do
      task = create(:task, status: "pending")
      call_count = 0

      allow(TaskProcessorService).to receive(:new).and_wrap_original do |method, *args|
        call_count += 1
        if call_count == 1
          double(call: nil).tap { |d|
            allow(d).to receive(:call).and_raise(TransientError, "timeout")
          }
        else
          method.call(*args)
        end
      end

      TaskProcessorJob.perform_now(task.id)

      task.reload
      expect(task.status).to eq("failed")
      expect(task.attempts).to eq(1)

      perform_enqueued_jobs

      task.reload
      expect(task.status).to eq("completed")
      expect(task.attempts).to eq(2)
    end
  end

  describe "cancellation path: create -> cancel -> verify" do
    it "cancels a pending task and job respects cancellation" do
      key = SecureRandom.uuid

      post "/api/v1/tasks",
        params: { task: { title: "Cancel me", priority: "low" } }.to_json,
        headers: { "Idempotency-Key" => key, "Content-Type" => "application/json" }

      task_id = JSON.parse(response.body)["id"]

      patch "/api/v1/tasks/#{task_id}/cancel", as: :json
      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)["status"]).to eq("cancelled")

      perform_enqueued_jobs

      get "/api/v1/tasks/#{task_id}", as: :json
      expect(JSON.parse(response.body)["status"]).to eq("cancelled")
    end
  end

  describe "idempotency path: duplicate requests" do
    it "returns cached response for duplicate idempotency key" do
      key = SecureRandom.uuid
      params = { task: { title: "Idempotent task", priority: "medium" } }.to_json
      headers = { "Idempotency-Key" => key, "Content-Type" => "application/json" }

      post "/api/v1/tasks", params: params, headers: headers
      expect(response).to have_http_status(202)
      first_body = JSON.parse(response.body)

      post "/api/v1/tasks", params: params, headers: headers
      expect(response).to have_http_status(409)

      expect(Task.where(idempotency_key: key).count).to eq(1)
    end
  end
end
