require 'rails_helper'

RSpec.describe TaskProcessorJob, type: :job do
  include ActiveJob::TestHelper

  describe "#perform" do
    context "happy path" do
      it "picks up a pending task, marks it processing, processes it, and marks completed" do
        task = create(:task, status: "pending")

        perform_enqueued_jobs do
          described_class.perform_later(task.id)
        end

        task.reload
        expect(task.status).to eq("completed")
        expect(task.result).to be_present
        expect(task.completed_at).to be_present
        expect(task.attempts).to eq(1)
      end
    end

    context "transient failure" do
      it "marks the task as failed and re-enqueues with backoff if retries remain" do
        task = create(:task, status: "pending", attempts: 0, max_attempts: 5)

        allow(TaskProcessorService).to receive(:new)
          .and_return(double(call: nil).tap { |d|
            allow(d).to receive(:call).and_raise(TransientError, "timeout")
          })

        described_class.perform_now(task.id)

        task.reload
        expect(task.status).to eq("failed")
        expect(task.error_message).to eq("timeout")
        expect(task.attempts).to eq(1)

        expect(enqueued_jobs.size).to eq(1)
        expect(enqueued_jobs.first["job_class"]).to eq("TaskProcessorJob")
      end

      it "does not re-enqueue when max attempts reached" do
        task = create(:task, status: "pending", attempts: 4, max_attempts: 5)

        allow(TaskProcessorService).to receive(:new)
          .and_return(double(call: nil).tap { |d|
            allow(d).to receive(:call).and_raise(TransientError, "timeout")
          })

        described_class.perform_now(task.id)

        task.reload
        expect(task.status).to eq("failed")
        expect(task.attempts).to eq(5)
        expect(enqueued_jobs.size).to eq(0)
      end
    end

    context "permanent failure" do
      it "marks the task as failed and does NOT re-enqueue" do
        task = create(:task, status: "pending")

        allow(TaskProcessorService).to receive(:new)
          .and_return(double(call: nil).tap { |d|
            allow(d).to receive(:call).and_raise(PermanentError, "invalid resource")
          })

        described_class.perform_now(task.id)

        task.reload
        expect(task.status).to eq("failed")
        expect(task.error_message).to eq("invalid resource")
        expect(enqueued_jobs.size).to eq(0)
      end
    end

    context "data corruption" do
      it "marks the task as failed and does NOT re-enqueue" do
        task = create(:task, status: "pending")

        allow(TaskProcessorService).to receive(:new)
          .and_return(double(call: nil).tap { |d|
            allow(d).to receive(:call).and_raise(DataCorruptionError, "checksum mismatch")
          })

        described_class.perform_now(task.id)

        task.reload
        expect(task.status).to eq("failed")
        expect(task.error_message).to eq("checksum mismatch")
        expect(enqueued_jobs.size).to eq(0)
      end
    end

    context "cancelled task" do
      it "skips processing entirely" do
        task = create(:task, :cancelled)

        expect(TaskProcessorService).not_to receive(:new)

        described_class.perform_now(task.id)

        task.reload
        expect(task.status).to eq("cancelled")
      end
    end

    context "already completed task" do
      it "skips processing (idempotent job)" do
        task = create(:task, :completed)

        expect(TaskProcessorService).not_to receive(:new)

        described_class.perform_now(task.id)

        task.reload
        expect(task.status).to eq("completed")
      end
    end

    context "stale object error" do
      it "re-fetches and retries gracefully" do
        task = create(:task, status: "pending")
        call_count = 0

        allow_any_instance_of(Task).to receive(:mark_processing!).and_wrap_original do |method, *args|
          call_count += 1
          if call_count == 1
            raise ActiveRecord::StaleObjectError.new(task, "update")
          else
            method.call(*args)
          end
        end

        described_class.perform_now(task.id)

        task.reload
        expect(task.status).to eq("completed")
      end
    end

    context "task not found" do
      it "handles gracefully without raising" do
        expect {
          described_class.perform_now(SecureRandom.uuid)
        }.not_to raise_error
      end
    end

    context "logging" do
      it "logs state transitions" do
        task = create(:task, status: "pending")

        expect(Rails.logger).to receive(:info).at_least(:twice)

        described_class.perform_now(task.id)
      end
    end
  end
end
