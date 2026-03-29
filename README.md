# Ajackus Task Manager

A production-quality Task Management API built with Ruby on Rails, demonstrating robust handling of real-world backend challenges: idempotency, retry logic, concurrency, duplicate prevention, and cancellation.

## Architecture

```
Client ─── POST /api/v1/tasks ──▶ TasksController
                                       │
                                       ▼
                              IdempotencyService
                              (advisory lock guard)
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
              New request        Completed dup       In-progress dup
              (create task)      (cached 200)        (409 Conflict)
                    │
                    ▼
              Task (pending)  ──▶  TaskProcessorJob
                                       │
                                       ▼
                              TaskProcessorService
                              (downstream simulator)
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
               Success            Transient err       Permanent err
               (completed)        (retry w/ backoff)  (failed, no retry)
```

### State Machine

```
                    ┌─────────┐
                    │ pending │
                    └────┬────┘
                   ┌─────┼─────────┐
                   ▼               ▼
            ┌────────────┐   ┌───────────┐
            │ processing │   │ cancelled │
            └─────┬──────┘   └───────────┘
            ┌─────┼──────┐
            ▼            ▼
      ┌───────────┐ ┌────────┐
      │ completed │ │ failed │──── retry ───▶ processing
      └───────────┘ └────────┘
```

## Design Decisions

### 1. Stripe-Style Idempotency

The `idempotency_keys` table caches the full HTTP response for each `Idempotency-Key`. Duplicate requests return the exact same response, achieving true HTTP idempotency. PostgreSQL advisory locks (`pg_advisory_xact_lock`) prevent race conditions when two requests with the same key arrive simultaneously.

### 2. Race-Condition-Free Ticket Numbers (QCK-1, QCK-2, ...)

Ticket numbers use a PostgreSQL sequence (`task_ticket_number_seq`). Sequences are atomic at the database level -- concurrent `nextval()` calls never return the same value, even under heavy load. This is more robust than application-level locking or MAX+1 queries.

### 3. Self-Managed Retries

Sidekiq's built-in retry is disabled (`sidekiq_options retry: 0`). The application manages retries with:
- **Error classification**: `TransientError` (retryable), `PermanentError` and `DataCorruptionError` (non-retryable)
- **Exponential backoff**: `5s * 2^attempts` between retries
- **Attempt budgeting**: Each task has `attempts` and `max_attempts` fields

This gives full control over retry behavior and prevents blindly retrying non-retryable errors.

### 4. Two-Layer Concurrency Protection

- **Optimistic locking** (`lock_version` column): Prevents two workers from stepping on each other's state transitions. `StaleObjectError` is caught and retried gracefully.
- **Advisory locks**: Prevent duplicate task creation at the database level, not just the application level.

### 5. State Machine Guards

All status transitions are validated in the model. Terminal states (`completed`, `cancelled`) cannot be transitioned out of. The job checks for cancellation before committing results.

### 6. UUID Primary Keys

Prevents enumeration attacks and makes IDs safe for external exposure in API responses.

## Edge Cases Handled

| Edge Case | How It's Handled |
|---|---|
| Duplicate requests | `Idempotency-Key` header + cached responses |
| Retry without duplication | Self-managed retries with attempt counter |
| Downstream transient failure | Exponential backoff retry |
| Downstream permanent failure | Marked failed, no retry |
| Data corruption | Marked failed, no retry |
| Concurrent task creation (same key) | `pg_advisory_xact_lock` |
| Concurrent state updates | Optimistic locking (`lock_version`) |
| Cancel during processing | Job checks status before committing |
| Ticket number race condition | PostgreSQL sequence (atomic `nextval`) |
| Task not found (deleted) | Job handles gracefully (no-op) |
| Already completed task re-processed | Job is idempotent (no-op) |
| Stale object during processing | Caught and re-fetched |

## Tech Stack

- Ruby 3.4.4, Rails 7.1.6 (API-only)
- PostgreSQL 16 (sequences, advisory locks, check constraints)
- Sidekiq + Redis (background jobs)
- RSpec (85 tests covering models, services, jobs, requests, integration, concurrency)

## Setup

### Prerequisites

- Ruby 3.4+
- PostgreSQL 16+
- Redis 7+

### Using Docker Compose (Recommended)

```bash
docker compose up --build -d
docker compose exec app bundle exec rails db:create db:migrate
docker compose exec -e RAILS_ENV=test app bundle exec rails db:create db:migrate
```

### Local Development

```bash
bundle install
rails db:create db:migrate
RAILS_ENV=test rails db:create db:migrate
```

### Running Tests

```bash
bundle exec rspec                    # Run all 85 tests
bundle exec rspec -f documentation   # Verbose output
bundle exec rspec spec/models/       # Models only
bundle exec rspec spec/integration/  # Integration only
```

### Starting the Server

```bash
# With Docker
docker compose up

# Locally
bundle exec rails server
bundle exec sidekiq -C config/sidekiq.yml  # In separate terminal
```

## API Documentation

### Create a Task

```
POST /api/v1/tasks
Headers: Idempotency-Key: <uuid>
Content-Type: application/json

{
  "task": {
    "title": "Deploy to production",
    "description": "Deploy v2.1.0",
    "priority": "critical"
  }
}

Response: 202 Accepted
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "ticket_number": "QCK-1",
  "title": "Deploy to production",
  "status": "pending",
  "priority": "critical",
  "created_at": "2026-03-27T12:00:00Z"
}
```

**Priority values**: `low`, `medium` (default), `high`, `critical`

### List Tasks

```
GET /api/v1/tasks
GET /api/v1/tasks?status=pending

Response: 200 OK
[{ "id": "...", "ticket_number": "QCK-1", "status": "pending", ... }]
```

### Get Task Details

```
GET /api/v1/tasks/:id

Response: 200 OK
{
  "id": "...",
  "ticket_number": "QCK-1",
  "title": "Deploy to production",
  "status": "completed",
  "attempts": 1,
  "result": { "processed_at": "...", "message": "..." },
  ...
}
```

### Cancel a Task

```
PATCH /api/v1/tasks/:id/cancel

Response: 200 OK (success)
Response: 409 Conflict (already completed/cancelled)
Response: 404 Not Found
```

### Error Response Format

All errors follow a consistent structure:

```json
{
  "error": {
    "code": "not_found",
    "message": "Resource not found"
  }
}
```

**Error codes**: `not_found`, `missing_idempotency_key`, `invalid_transition`

## HTTP Status Codes

| Code | Meaning |
|---|---|
| 200 | Success / Cached idempotent response |
| 202 | Accepted (task queued for processing) |
| 400 | Bad Request (validation error / missing header) |
| 404 | Not Found |
| 409 | Conflict (duplicate in-progress / invalid transition) |
| 500 | Internal Server Error |

## Project Structure

```
app/
  controllers/
    application_controller.rb          # Global error handling
    concerns/request_logging.rb        # Request ID correlation
    api/v1/tasks_controller.rb         # REST endpoints
  models/
    task.rb                            # State machine, validations, scopes
    idempotency_key.rb                 # Response caching
  jobs/
    task_processor_job.rb              # Self-managed retries, error classification
  services/
    task_processor_service.rb          # Downstream processing simulator
    idempotency_service.rb             # Advisory lock + idempotency logic
  errors/
    transient_error.rb                 # Retryable errors
    permanent_error.rb                 # Non-retryable errors
    data_corruption_error.rb           # Data integrity failures
spec/
  models/           (37 tests)         # Validations, transitions, locking
  services/         (13 tests)         # Service logic
  jobs/             (10 tests)         # Job behavior, error handling
  requests/         (16 tests)         # API endpoint testing
  integration/       (9 tests)         # Full workflows + concurrency
```

## What I'd Add in Production

- **Authentication**: JWT/API key authentication
- **Rate limiting**: Rack::Attack or similar
- **Circuit breaker**: For downstream service calls
- **Dead letter queue**: For permanently failed tasks that need manual review
- **Metrics/APM**: Datadog, New Relic, or Prometheus
- **Pagination**: Cursor-based pagination for task listing
- **Webhook notifications**: Notify clients when tasks complete
- **TTL cleanup**: Periodic job to clean old idempotency keys
