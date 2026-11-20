class CreateCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :calls do |t|
      t.string :call_id, null: false
      t.string :caller, null: false
      t.string :callee, null: false
      t.datetime :started_at, null: false
      t.datetime :answered_at
      t.datetime :ended_at, null: false
      t.integer :duration_seconds, null: false
      t.string :status, null: false
      t.timestamps
    end

    add_index :calls, :call_id, unique: true
    add_index :calls, :caller
    add_index :calls, :callee
    add_index :calls, :status
    add_index :calls, :started_at

    add_check_constraint :calls, "length(btrim(call_id)) > 0 AND length(btrim(caller)) > 0 AND length(btrim(callee)) > 0", name: "calls_identifiers_not_blank"
    add_check_constraint :calls, "status IN ('answered', 'missed', 'rejected')", name: "calls_valid_status"
    add_check_constraint :calls, "duration_seconds >= 0", name: "calls_nonnegative_duration"
    add_check_constraint :calls, "started_at <= ended_at AND (answered_at IS NULL OR (started_at <= answered_at AND answered_at <= ended_at))", name: "calls_valid_times"
    add_check_constraint :calls, "(status = 'answered' AND answered_at IS NOT NULL) OR (status IN ('missed', 'rejected') AND answered_at IS NULL AND duration_seconds = 0)", name: "calls_status_matches_answer"
  end
end
