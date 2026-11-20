require "rails_helper"

RSpec.describe Call, type: :model do
  let(:attributes) do
    { call_id: "call-1", caller: "1001", callee: "1002",
      started_at: Time.utc(2026, 11, 20, 14, 30), answered_at: Time.utc(2026, 11, 20, 14, 30, 15),
      ended_at: Time.utc(2026, 11, 20, 14, 35), duration_seconds: 285, status: "answered" }
  end

  it "persists a completed call" do
    expect(described_class.create!(attributes).reload.call_id).to eq("call-1")
  end

  it "accepts unanswered calls with no answer and zero duration" do
    %w[missed rejected].each do |status|
      expect(described_class.new(attributes.merge(status: status, answered_at: nil, duration_seconds: 0))).to be_valid
    end
  end

  it "validates presence, uniqueness, status, duration and temporal consistency" do
    described_class.create!(attributes)
    expect(described_class.new(attributes)).not_to be_valid
    [ { caller: " " }, { status: "unknown" }, { duration_seconds: -1 },
      { ended_at: attributes[:started_at] - 1 }, { answered_at: attributes[:ended_at] + 1 },
      { answered_at: nil }, { status: "missed", answered_at: nil, duration_seconds: 1 } ].each do |changes|
      expect(described_class.new(attributes.merge(call_id: "other").merge(changes))).not_to be_valid
    end
  end

  it "enforces constraints in PostgreSQL when validations are bypassed" do
    described_class.create!(attributes)
    invalid = [ { call_id: "call-1" }, { caller: nil }, { callee: " " }, { status: "other" },
                { duration_seconds: -1 }, { ended_at: attributes[:started_at] - 1 },
                { answered_at: attributes[:started_at] - 1 }, { answered_at: attributes[:ended_at] + 1 },
                { answered_at: nil }, { status: "missed", answered_at: nil, duration_seconds: 1 },
                { status: "rejected" } ]
    invalid.each_with_index do |changes, index|
      expect do
        described_class.transaction(requires_new: true) do
          described_class.insert_all!([attributes.merge(call_id: "other-#{index}").merge(changes)])
        end
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  it "has indexes for call identity and query filters" do
    indexes = ActiveRecord::Base.connection.indexes(:calls)
    expect(indexes).to include(have_attributes(columns: ["call_id"], unique: true))
    %w[caller callee status started_at].each do |column|
      expect(indexes).to include(have_attributes(columns: [column]))
    end
  end
end
