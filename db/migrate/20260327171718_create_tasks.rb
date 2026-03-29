class CreateTasks < ActiveRecord::Migration[7.1]
  def change
    execute <<-SQL
      CREATE SEQUENCE task_ticket_number_seq START 1;
    SQL

    create_table :tasks, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :ticket_number,   null: false
      t.string   :idempotency_key, null: false
      t.string   :title,           null: false
      t.text     :description
      t.string   :priority,        null: false, default: "medium"
      t.string   :status,          null: false, default: "pending"
      t.jsonb    :payload,         default: {}
      t.jsonb    :result
      t.text     :error_message
      t.integer  :attempts,        null: false, default: 0
      t.integer  :max_attempts,    null: false, default: 5
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :cancelled_at
      t.integer  :lock_version,    null: false, default: 0

      t.timestamps
    end

    add_index :tasks, :ticket_number, unique: true
    add_index :tasks, :idempotency_key, unique: true
    add_index :tasks, :status

    execute <<-SQL
      ALTER TABLE tasks ADD CONSTRAINT tasks_status_check
        CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled'));
    SQL

    execute <<-SQL
      ALTER TABLE tasks ADD CONSTRAINT tasks_priority_check
        CHECK (priority IN ('low', 'medium', 'high', 'critical'));
    SQL

    reversible do |dir|
      dir.down do
        execute "DROP SEQUENCE IF EXISTS task_ticket_number_seq;"
      end
    end
  end
end
