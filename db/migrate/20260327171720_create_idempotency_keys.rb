class CreateIdempotencyKeys < ActiveRecord::Migration[7.1]
  def change
    create_table :idempotency_keys do |t|
      t.string  :key,           null: false
      t.uuid    :task_id,       null: false
      t.integer :response_code
      t.jsonb   :response_body

      t.datetime :created_at,   null: false
    end

    add_index :idempotency_keys, :key, unique: true
    add_index :idempotency_keys, :task_id
    add_foreign_key :idempotency_keys, :tasks
  end
end
