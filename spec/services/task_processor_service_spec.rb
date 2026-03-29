require 'rails_helper'

RSpec.describe TaskProcessorService do
  let(:task) { create(:task) }

  describe "#call" do
    context "when processing succeeds" do
      it "returns a result hash with processed data" do
        service = described_class.new(task)
        result = service.call

        expect(result).to be_a(Hash)
        expect(result).to have_key(:processed_at)
        expect(result).to have_key(:task_id)
        expect(result[:task_id]).to eq(task.id)
      end
    end

    context "when a transient error occurs" do
      it "raises TransientError" do
        service = described_class.new(task, simulate: :transient_failure)

        expect { service.call }.to raise_error(TransientError) do |error|
          expect(error.message).to include("transient")
        end
      end
    end

    context "when a permanent error occurs" do
      it "raises PermanentError" do
        service = described_class.new(task, simulate: :permanent_failure)

        expect { service.call }.to raise_error(PermanentError) do |error|
          expect(error.message).to include("permanent")
        end
      end
    end

    context "when data corruption is detected" do
      it "raises DataCorruptionError" do
        service = described_class.new(task, simulate: :data_corruption)

        expect { service.call }.to raise_error(DataCorruptionError)
      end
    end

    context "when processing is slow" do
      it "still completes and returns a result" do
        service = described_class.new(task, simulate: :slow_processing)
        result = service.call

        expect(result).to be_a(Hash)
        expect(result[:task_id]).to eq(task.id)
      end
    end
  end
end
