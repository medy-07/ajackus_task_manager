FactoryBot.define do
  factory :idempotency_key do
    key { SecureRandom.uuid }
    task
    response_code { 202 }
    response_body { { id: SecureRandom.uuid, status: "pending" } }
  end
end
