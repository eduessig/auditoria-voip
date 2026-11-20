class AddFingerprintsToProcessedMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :processed_messages, :envelope_fingerprint, :string
    add_column :processed_messages, :call_fingerprint, :string
  end
end
