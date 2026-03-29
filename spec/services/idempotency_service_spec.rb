require 'rails_helper'

RSpec.describe IdempotencyService do
  describe "#execute" do
    let(:valid_params) { { title: "Test Task", description: "A test", priority: "high" } }
    let(:idempotency_key) { SecureRandom.uuid }

    context "with a new idempotency key" do
      it "creates a task and returns 202 status" do
        service = described_class.new(idempotency_key, valid_params)
        result = service.execute

        expect(result[:status]).to eq(202)
        expect(result[:body][:id]).to be_present
        expect(result[:body][:status]).to eq("pending")
        expect(result[:body][:ticket_number]).to match(/\AQCK-\d+\z/)
      end

      it "persists the task in the database" do
        service = described_class.new(idempotency_key, valid_params)

        expect { service.execute }.to change(Task, :count).by(1)
      end

      it "creates an idempotency key record with cached response" do
        service = described_class.new(idempotency_key, valid_params)

        expect { service.execute }.to change(IdempotencyKey, :count).by(1)

        idem = IdempotencyKey.find_by(key: idempotency_key)
        expect(idem.response_code).to eq(202)
        expect(idem.response_body).to be_present
      end

      it "enqueues a TaskProcessorJob" do
        service = described_class.new(idempotency_key, valid_params)

        expect {
          service.execute
        }.to have_enqueued_job(TaskProcessorJob)
      end
    end

    context "with a duplicate key for a completed task" do
      it "returns the cached response" do
        task = create(:task, :completed, idempotency_key: idempotency_key)
        cached_body = { id: task.id, status: "completed" }
        create(:idempotency_key,
          key: idempotency_key,
          task: task,
          response_code: 200,
          response_body: cached_body
        )

        service = described_class.new(idempotency_key, valid_params)
        result = service.execute

        expect(result[:status]).to eq(200)
        expect(result[:body]["status"]).to eq("completed")
      end

      it "does not create a new task" do
        task = create(:task, :completed, idempotency_key: idempotency_key)
        create(:idempotency_key,
          key: idempotency_key,
          task: task,
          response_code: 200,
          response_body: { id: task.id, status: "completed" }
        )

        service = described_class.new(idempotency_key, valid_params)

        expect { service.execute }.not_to change(Task, :count)
      end
    end

    context "with a duplicate key for an in-progress task" do
      it "returns 409 conflict" do
        task = create(:task, :processing, idempotency_key: idempotency_key)
        create(:idempotency_key,
          key: idempotency_key,
          task: task,
          response_code: 202,
          response_body: { id: task.id, status: "processing" }
        )

        service = described_class.new(idempotency_key, valid_params)
        result = service.execute

        expect(result[:status]).to eq(409)
        expect(result[:body][:error]).to include("already being processed")
      end
    end

    context "with invalid task params" do
      it "returns 400 with validation errors" do
        service = described_class.new(idempotency_key, { title: "" })
        result = service.execute

        expect(result[:status]).to eq(400)
        expect(result[:body][:errors]).to be_present
      end
    end
  end
end
