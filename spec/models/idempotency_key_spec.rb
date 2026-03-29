require 'rails_helper'

RSpec.describe IdempotencyKey, type: :model do
  subject { build(:idempotency_key) }

  describe "validations" do
    it { should validate_presence_of(:key) }
    it { should validate_uniqueness_of(:key) }
  end

  describe "associations" do
    it { should belong_to(:task) }
  end

  describe "response caching" do
    it "stores and retrieves the cached response" do
      task = create(:task)
      idem_key = create(:idempotency_key,
        task: task,
        response_code: 202,
        response_body: { id: task.id, status: "pending" }
      )

      idem_key.reload
      expect(idem_key.response_code).to eq(202)
      expect(idem_key.response_body).to include("status" => "pending")
    end
  end
end
