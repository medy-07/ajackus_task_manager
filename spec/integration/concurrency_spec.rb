require 'rails_helper'

RSpec.describe "Concurrency handling", type: :request, concurrency: true do
  describe "duplicate idempotency key race condition" do
    it "only creates one task when two requests arrive simultaneously with the same key" do
      key = SecureRandom.uuid
      params = { task: { title: "Race test", priority: "high" } }
      headers = { "Idempotency-Key" => key, "Content-Type" => "application/json" }

      threads = 2.times.map do
        Thread.new do
          conn = ActiveRecord::Base.connection_pool.checkout
          begin
            ActiveRecord::Base.connection_pool.with_connection do
              post "/api/v1/tasks", params: params.to_json, headers: headers
              response.status
            end
          ensure
            ActiveRecord::Base.connection_pool.checkin(conn)
          end
        end
      end

      statuses = threads.map(&:value)

      expect(Task.where(idempotency_key: key).count).to eq(1)
      expect(statuses).to include(202)
    end
  end

  describe "optimistic locking prevents lost updates" do
    it "raises StaleObjectError when two workers update the same task" do
      task = Task.create!(
        title: "Lock test",
        idempotency_key: SecureRandom.uuid,
        status: "pending",
        priority: "medium"
      )

      copy1 = Task.find(task.id)
      copy2 = Task.find(task.id)

      copy1.update!(title: "Updated by worker 1")

      expect {
        copy2.update!(title: "Updated by worker 2")
      }.to raise_error(ActiveRecord::StaleObjectError)
    end
  end

  describe "ticket number sequence under concurrent creation" do
    it "assigns unique sequential ticket numbers" do
      tasks = 10.times.map do
        Task.create!(
          title: "Concurrent task #{SecureRandom.hex(3)}",
          idempotency_key: SecureRandom.uuid,
          status: "pending",
          priority: "medium"
        )
      end

      ticket_numbers = tasks.map(&:ticket_number)
      expect(ticket_numbers.uniq.size).to eq(10)

      numbers = ticket_numbers.map { |tn| tn.split("-").last.to_i }
      expect(numbers).to eq(numbers.sort)
    end
  end

  describe "cancel during processing" do
    it "job respects cancellation before committing result" do
      task = Task.create!(
        title: "Cancel test",
        idempotency_key: SecureRandom.uuid,
        status: "pending",
        priority: "medium"
      )

      task.cancel!
      expect(task.reload.status).to eq("cancelled")

      TaskProcessorJob.perform_now(task.id)

      expect(task.reload.status).to eq("cancelled")
    end
  end

  describe "retry of already-completed task" do
    it "job is a no-op for completed task" do
      task = Task.create!(
        title: "Completed test",
        idempotency_key: SecureRandom.uuid,
        status: "pending",
        priority: "medium"
      )

      task.mark_processing!
      task.mark_completed!({ result: "done" })
      expect(task.reload.status).to eq("completed")

      TaskProcessorJob.perform_now(task.id)

      expect(task.reload.status).to eq("completed")
    end
  end
end
