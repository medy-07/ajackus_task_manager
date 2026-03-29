FactoryBot.define do
  factory :task do
    title { Faker::Lorem.sentence(word_count: 3) }
    description { Faker::Lorem.paragraph }
    priority { "medium" }
    status { "pending" }
    idempotency_key { SecureRandom.uuid }
    ticket_number { nil }
    payload { { source: "api", metadata: {} } }

    trait :processing do
      status { "processing" }
      started_at { Time.current }
      attempts { 1 }
    end

    trait :completed do
      status { "completed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      attempts { 1 }
      result { { message: "Processed successfully" } }
    end

    trait :failed do
      status { "failed" }
      started_at { 1.hour.ago }
      attempts { 1 }
      error_message { "Something went wrong" }
    end

    trait :cancelled do
      status { "cancelled" }
      cancelled_at { Time.current }
    end

    trait :retryable do
      status { "failed" }
      attempts { 2 }
      max_attempts { 5 }
      error_message { "Transient error" }
    end

    trait :exhausted do
      status { "failed" }
      attempts { 5 }
      max_attempts { 5 }
      error_message { "Max retries exhausted" }
    end

    trait :high_priority do
      priority { "high" }
    end

    trait :critical do
      priority { "critical" }
    end
  end
end
