require 'rails_helper'

RSpec.describe "Api::V1::Tasks", type: :request do
  let(:valid_headers) { { "Idempotency-Key" => SecureRandom.uuid } }
  let(:valid_params) { { task: { title: "Deploy service", description: "Deploy to prod", priority: "high" } } }

  describe "POST /api/v1/tasks" do
    context "with valid params and new idempotency key" do
      it "returns 202 Accepted and creates a task" do
        expect {
          post "/api/v1/tasks", params: valid_params, headers: valid_headers, as: :json
        }.to change(Task, :count).by(1)

        expect(response).to have_http_status(202)

        body = JSON.parse(response.body)
        expect(body["id"]).to be_present
        expect(body["ticket_number"]).to match(/\AQCK-\d+\z/)
        expect(body["status"]).to eq("pending")
        expect(body["title"]).to eq("Deploy service")
      end

      it "enqueues a background job" do
        expect {
          post "/api/v1/tasks", params: valid_params, headers: valid_headers, as: :json
        }.to have_enqueued_job(TaskProcessorJob)
      end
    end

    context "with duplicate idempotency key for completed task" do
      it "returns 200 with cached response" do
        key = SecureRandom.uuid
        task = create(:task, :completed, idempotency_key: key)
        create(:idempotency_key,
          key: key,
          task: task,
          response_code: 200,
          response_body: { id: task.id, status: "completed", ticket_number: task.ticket_number }
        )

        post "/api/v1/tasks", params: valid_params, headers: { "Idempotency-Key" => key }, as: :json

        expect(response).to have_http_status(200)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("completed")
      end
    end

    context "with duplicate idempotency key for in-progress task" do
      it "returns 409 Conflict" do
        key = SecureRandom.uuid
        task = create(:task, :processing, idempotency_key: key)
        create(:idempotency_key,
          key: key,
          task: task,
          response_code: 202,
          response_body: { id: task.id, status: "processing" }
        )

        post "/api/v1/tasks", params: valid_params, headers: { "Idempotency-Key" => key }, as: :json

        expect(response).to have_http_status(409)
      end
    end

    context "with missing title" do
      it "returns 400 Bad Request" do
        post "/api/v1/tasks",
          params: { task: { title: "", description: "No title" } },
          headers: valid_headers, as: :json

        expect(response).to have_http_status(400)
        body = JSON.parse(response.body)
        expect(body["errors"]).to be_present
      end
    end

    context "with missing Idempotency-Key header" do
      it "returns 400 Bad Request" do
        post "/api/v1/tasks", params: valid_params, as: :json

        expect(response).to have_http_status(400)
        body = JSON.parse(response.body)
        expect(body["error"]["code"]).to eq("missing_idempotency_key")
      end
    end
  end

  describe "GET /api/v1/tasks" do
    before do
      create(:task, status: "pending", title: "Task A")
      create(:task, :completed, title: "Task B")
      create(:task, :failed, title: "Task C")
    end

    it "returns 200 with all tasks" do
      get "/api/v1/tasks", as: :json

      expect(response).to have_http_status(200)
      body = JSON.parse(response.body)
      expect(body.size).to eq(3)
    end

    it "filters by status" do
      get "/api/v1/tasks?status=completed", as: :json

      expect(response).to have_http_status(200)
      body = JSON.parse(response.body)
      expect(body.size).to eq(1)
      expect(body.first["status"]).to eq("completed")
    end
  end

  describe "GET /api/v1/tasks/:id" do
    it "returns 200 with task details" do
      task = create(:task)

      get "/api/v1/tasks/#{task.id}", as: :json

      expect(response).to have_http_status(200)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(task.id)
      expect(body["ticket_number"]).to be_present
      expect(body["status"]).to eq("pending")
    end

    it "returns 404 when task not found" do
      get "/api/v1/tasks/#{SecureRandom.uuid}", as: :json

      expect(response).to have_http_status(404)
      body = JSON.parse(response.body)
      expect(body["error"]["code"]).to eq("not_found")
    end
  end

  describe "PATCH /api/v1/tasks/:id/cancel" do
    context "when task is pending" do
      it "returns 200 and cancels the task" do
        task = create(:task, status: "pending")

        patch "/api/v1/tasks/#{task.id}/cancel", as: :json

        expect(response).to have_http_status(200)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("cancelled")
        expect(task.reload.status).to eq("cancelled")
      end
    end

    context "when task is processing" do
      it "returns 200 and cancels the task" do
        task = create(:task, :processing)

        patch "/api/v1/tasks/#{task.id}/cancel", as: :json

        expect(response).to have_http_status(200)
        expect(task.reload.status).to eq("cancelled")
      end
    end

    context "when task is already completed" do
      it "returns 409 Conflict" do
        task = create(:task, :completed)

        patch "/api/v1/tasks/#{task.id}/cancel", as: :json

        expect(response).to have_http_status(409)
        body = JSON.parse(response.body)
        expect(body["error"]["code"]).to eq("invalid_transition")
      end
    end

    context "when task is already cancelled" do
      it "returns 409 Conflict" do
        task = create(:task, :cancelled)

        patch "/api/v1/tasks/#{task.id}/cancel", as: :json

        expect(response).to have_http_status(409)
      end
    end

    context "when task not found" do
      it "returns 404" do
        patch "/api/v1/tasks/#{SecureRandom.uuid}/cancel", as: :json

        expect(response).to have_http_status(404)
      end
    end
  end

  describe "error response format" do
    it "returns consistent JSON error structure" do
      get "/api/v1/tasks/#{SecureRandom.uuid}", as: :json

      body = JSON.parse(response.body)
      expect(body).to have_key("error")
      expect(body["error"]).to have_key("code")
      expect(body["error"]).to have_key("message")
    end
  end
end
