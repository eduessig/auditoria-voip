require "rails_helper"

RSpec.describe ProcessedMessage, type: :model do
  let!(:call) do
    Call.create!(call_id: "call-1", caller: "1001", callee: "1002", started_at: Time.utc(2026, 1, 1),
                 ended_at: Time.utc(2026, 1, 1, 0, 1), duration_seconds: 0, status: "missed")
  end
  let(:message_id) { "38d8817d-29eb-4f69-a45d-1d6dd51d5a2b" }
  let(:attributes) { { message_id: message_id, call_id: call.id, processed_at: Time.utc(2026, 1, 1, 0, 2) } }

  it "persists a message associated with a call" do
    expect(described_class.create!(attributes).reload.call).to eq(call)
  end

  it "validates required fields and uniqueness" do
    described_class.create!(attributes)
    expect(described_class.new(attributes)).not_to be_valid
    expect(described_class.new(message_id: nil, call: nil, processed_at: nil)).not_to be_valid
  end

  it "enforces uniqueness, nullability and the foreign key in PostgreSQL" do
    described_class.create!(attributes)
    [attributes, attributes.merge(message_id: nil), attributes.merge(message_id: SecureRandom.uuid, call_id: nil),
     attributes.merge(message_id: SecureRandom.uuid, processed_at: nil),
     attributes.merge(message_id: SecureRandom.uuid, call_id: -1)].each do |values|
      expect do
        described_class.transaction(requires_new: true) { described_class.insert_all!([values]) }
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  it "indexes message identity uniquely and permits multiple messages per call" do
    indexes = ActiveRecord::Base.connection.indexes(:processed_messages)
    expect(indexes).to include(have_attributes(columns: ["message_id"], unique: true))
    expect(indexes).to include(have_attributes(columns: ["call_id"], unique: false))
    described_class.create!(attributes)
    expect { described_class.create!(attributes.merge(message_id: SecureRandom.uuid)) }.to change(described_class, :count).by(1)
  end
end
