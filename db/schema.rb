# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_03_27_171720) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "idempotency_keys", force: :cascade do |t|
    t.string "key", null: false
    t.uuid "task_id", null: false
    t.integer "response_code"
    t.jsonb "response_body"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_idempotency_keys_on_key", unique: true
    t.index ["task_id"], name: "index_idempotency_keys_on_task_id"
  end

  create_table "tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "ticket_number", null: false
    t.string "idempotency_key", null: false
    t.string "title", null: false
    t.text "description"
    t.string "priority", default: "medium", null: false
    t.string "status", default: "pending", null: false
    t.jsonb "payload", default: {}
    t.jsonb "result"
    t.text "error_message"
    t.integer "attempts", default: 0, null: false
    t.integer "max_attempts", default: 5, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "cancelled_at"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_tasks_on_idempotency_key", unique: true
    t.index ["status"], name: "index_tasks_on_status"
    t.index ["ticket_number"], name: "index_tasks_on_ticket_number", unique: true
    t.check_constraint "priority::text = ANY (ARRAY['low'::character varying, 'medium'::character varying, 'high'::character varying, 'critical'::character varying]::text[])", name: "tasks_priority_check"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'processing'::character varying, 'completed'::character varying, 'failed'::character varying, 'cancelled'::character varying]::text[])", name: "tasks_status_check"
  end

  add_foreign_key "idempotency_keys", "tasks"
end
