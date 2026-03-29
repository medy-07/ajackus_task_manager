require 'rails_helper'

RSpec.describe Task, type: :model do
  describe "validations" do
    subject { create(:task) }

    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:idempotency_key) }
    it { should validate_uniqueness_of(:idempotency_key) }
    it { should validate_uniqueness_of(:ticket_number) }
    it { should validate_inclusion_of(:status).in_array(%w[pending processing completed failed cancelled]) }
    it { should validate_inclusion_of(:priority).in_array(%w[low medium high critical]) }
  end

  describe "associations" do
    it { should have_one(:idempotency_key_record).class_name("IdempotencyKey") }
  end

  describe "ticket_number generation" do
    it "auto-generates a sequential ticket number on create" do
      task1 = create(:task, ticket_number: nil)
      task2 = create(:task, ticket_number: nil)

      expect(task1.ticket_number).to match(/\AQCK-\d+\z/)
      expect(task2.ticket_number).to match(/\AQCK-\d+\z/)

      num1 = task1.ticket_number.split("-").last.to_i
      num2 = task2.ticket_number.split("-").last.to_i
      expect(num2).to eq(num1 + 1)
    end

    it "uses PostgreSQL sequence to avoid race conditions" do
      tasks = Array.new(5) { create(:task, ticket_number: nil) }
      numbers = tasks.map { |t| t.ticket_number.split("-").last.to_i }
      expect(numbers).to eq(numbers.sort)
      expect(numbers.uniq.size).to eq(5)
    end

    it "does not overwrite an explicitly provided ticket_number" do
      task = create(:task, ticket_number: "QCK-999")
      expect(task.ticket_number).to eq("QCK-999")
    end
  end

  describe "state transitions" do
    describe "#mark_processing!" do
      it "transitions from pending to processing" do
        task = create(:task, status: "pending")
        task.mark_processing!

        expect(task.reload.status).to eq("processing")
        expect(task.started_at).to be_present
        expect(task.attempts).to eq(1)
      end

      it "transitions from failed to processing (retry)" do
        task = create(:task, :retryable)
        task.mark_processing!

        expect(task.reload.status).to eq("processing")
        expect(task.attempts).to eq(3)
      end

      it "raises error when transitioning from completed" do
        task = create(:task, :completed)
        expect { task.mark_processing! }.to raise_error(Task::InvalidTransitionError)
      end

      it "raises error when transitioning from cancelled" do
        task = create(:task, :cancelled)
        expect { task.mark_processing! }.to raise_error(Task::InvalidTransitionError)
      end

      it "raises error when retries are exhausted" do
        task = create(:task, :exhausted)
        expect { task.mark_processing! }.to raise_error(Task::InvalidTransitionError)
      end
    end

    describe "#mark_completed!" do
      it "transitions from processing to completed" do
        task = create(:task, :processing)
        result = { output: "done" }
        task.mark_completed!(result)

        expect(task.reload.status).to eq("completed")
        expect(task.completed_at).to be_present
        expect(task.result).to eq("output" => "done")
      end

      it "raises error when not in processing state" do
        task = create(:task, status: "pending")
        expect { task.mark_completed!({}) }.to raise_error(Task::InvalidTransitionError)
      end
    end

    describe "#mark_failed!" do
      it "transitions from processing to failed" do
        task = create(:task, :processing)
        task.mark_failed!("Connection timeout")

        expect(task.reload.status).to eq("failed")
        expect(task.error_message).to eq("Connection timeout")
      end

      it "raises error when not in processing state" do
        task = create(:task, status: "pending")
        expect { task.mark_failed!("error") }.to raise_error(Task::InvalidTransitionError)
      end
    end

    describe "#cancel!" do
      it "transitions from pending to cancelled" do
        task = create(:task, status: "pending")
        task.cancel!

        expect(task.reload.status).to eq("cancelled")
        expect(task.cancelled_at).to be_present
      end

      it "transitions from processing to cancelled" do
        task = create(:task, :processing)
        task.cancel!

        expect(task.reload.status).to eq("cancelled")
      end

      it "raises error when already completed" do
        task = create(:task, :completed)
        expect { task.cancel! }.to raise_error(Task::InvalidTransitionError)
      end

      it "raises error when already cancelled" do
        task = create(:task, :cancelled)
        expect { task.cancel! }.to raise_error(Task::InvalidTransitionError)
      end
    end
  end

  describe "optimistic locking" do
    it "raises StaleObjectError on concurrent updates" do
      task = create(:task, status: "pending")

      task_copy1 = Task.find(task.id)
      task_copy2 = Task.find(task.id)

      task_copy1.update!(title: "Updated by copy1")

      expect {
        task_copy2.update!(title: "Updated by copy2")
      }.to raise_error(ActiveRecord::StaleObjectError)
    end
  end

  describe "scopes" do
    before do
      create(:task, :retryable)
      create(:task, :exhausted)
      create(:task, :completed)
      create(:task, :cancelled)
      create(:task, status: "pending")
      create(:task, :processing)
    end

    describe ".retryable" do
      it "returns failed tasks with remaining attempts" do
        tasks = Task.retryable
        expect(tasks.count).to eq(1)
        expect(tasks.first.status).to eq("failed")
        expect(tasks.first.attempts).to be < tasks.first.max_attempts
      end
    end

    describe ".cancellable" do
      it "returns pending and processing tasks" do
        tasks = Task.cancellable
        expect(tasks.count).to eq(2)
        expect(tasks.pluck(:status).sort).to eq(%w[pending processing])
      end
    end

    describe ".by_status" do
      it "filters tasks by status" do
        expect(Task.by_status("completed").count).to eq(1)
        expect(Task.by_status("failed").count).to eq(2)
      end
    end
  end

  describe "#retryable?" do
    it "returns true for failed task with remaining attempts" do
      task = build(:task, :retryable)
      expect(task.retryable?).to be true
    end

    it "returns false for failed task with exhausted attempts" do
      task = build(:task, :exhausted)
      expect(task.retryable?).to be false
    end

    it "returns false for completed task" do
      task = build(:task, :completed)
      expect(task.retryable?).to be false
    end
  end

  describe "#terminal?" do
    it "returns true for completed task" do
      expect(build(:task, :completed).terminal?).to be true
    end

    it "returns true for cancelled task" do
      expect(build(:task, :cancelled).terminal?).to be true
    end

    it "returns false for pending task" do
      expect(build(:task, status: "pending").terminal?).to be false
    end
  end
end
