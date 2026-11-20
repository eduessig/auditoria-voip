class CreateProcessedMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :processed_messages do |t|
      t.uuid :message_id, null: false
      t.references :call, null: false, foreign_key: true
      t.datetime :processed_at, null: false
    end

    add_index :processed_messages, :message_id, unique: true
  end
end
