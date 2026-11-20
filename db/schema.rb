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

ActiveRecord::Schema[8.1].define(version: 2026_11_20_000003) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "calls", force: :cascade do |t|
    t.string "call_id", null: false
    t.string "caller", null: false
    t.string "callee", null: false
    t.datetime "started_at", null: false
    t.datetime "answered_at"
    t.datetime "ended_at", null: false
    t.integer "duration_seconds", null: false
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["call_id"], name: "index_calls_on_call_id", unique: true
    t.index ["callee"], name: "index_calls_on_callee"
    t.index ["caller"], name: "index_calls_on_caller"
    t.index ["started_at"], name: "index_calls_on_started_at"
    t.index ["status"], name: "index_calls_on_status"
    t.check_constraint "duration_seconds >= 0", name: "calls_nonnegative_duration"
    t.check_constraint "length(btrim(call_id::text)) > 0 AND length(btrim(caller::text)) > 0 AND length(btrim(callee::text)) > 0", name: "calls_identifiers_not_blank"
    t.check_constraint "started_at <= ended_at AND (answered_at IS NULL OR started_at <= answered_at AND answered_at <= ended_at)", name: "calls_valid_times"
    t.check_constraint "status::text = 'answered'::text AND answered_at IS NOT NULL OR (status::text = ANY (ARRAY['missed'::character varying, 'rejected'::character varying]::text[])) AND answered_at IS NULL AND duration_seconds = 0", name: "calls_status_matches_answer"
    t.check_constraint "status::text = ANY (ARRAY['answered'::character varying, 'missed'::character varying, 'rejected'::character varying]::text[])", name: "calls_valid_status"
  end

  create_table "processed_messages", force: :cascade do |t|
    t.uuid "message_id", null: false
    t.bigint "call_id", null: false
    t.datetime "processed_at", null: false
    t.string "envelope_fingerprint"
    t.string "call_fingerprint"
    t.index ["call_id"], name: "index_processed_messages_on_call_id"
    t.index ["message_id"], name: "index_processed_messages_on_message_id", unique: true
  end

  add_foreign_key "processed_messages", "calls"
end
