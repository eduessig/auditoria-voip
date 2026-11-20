require "rails_helper"
require "json"

RSpec.describe CallCompletedProcessor do
  let(:message) { JSON.parse(File.read(Rails.root.join("contracts/call.completed.v1.example.json"))) }

  it "persists a call and message atomically and accepts an equivalent redelivery" do
    expect(described_class.call(message)).to eq(:processed)
    reordered = JSON.parse(JSON.generate(message.reverse_each.to_h))
    reordered["occurredAt"] = "2026-11-20T11:35:00-03:00"
    expect(described_class.call(reordered)).to eq(:duplicate)
    expect(Call.count).to eq(1)
    expect(ProcessedMessage.count).to eq(1)
  end

  it "accepts a new message for the same call only when its data matches" do
    described_class.call(message)
    other = message.deep_dup
    other["messageId"] = SecureRandom.uuid
    expect(described_class.call(other)).to eq(:processed)
    other["messageId"] = SecureRandom.uuid
    other["payload"]["caller"] = "changed"
    expect { described_class.call(other) }.to raise_error(described_class::Conflict)
    expect(Call.count).to eq(1)
    expect(ProcessedMessage.count).to eq(2)
  end

  it "rejects a reused message ID with a different envelope" do
    described_class.call(message)
    message["correlationId"] = SecureRandom.uuid
    expect { described_class.call(message) }.to raise_error(described_class::Conflict)
    expect(ProcessedMessage.count).to eq(1)
  end

  it "rejects invalid envelopes, payloads and temporal order without persisting" do
    variants = []
    variants << "{"
    variants << message.merge("extra" => true)
    variants << message.merge("messageId" => "invalid")
    variants << message.merge("version" => 1.0)
    variants << message.deep_dup.tap { |m| m["payload"]["answeredAt"] = nil }
    variants << message.deep_dup.tap { |m| m["payload"]["endedAt"] = "2026-02-30T14:29:00Z" }
    variants << message.deep_dup.tap { |m| m["payload"]["endedAt"] = "2026-11-20T14:29:00Z" }
    variants << message.deep_dup.tap { |m| m["occurredAt"] = "2026-11-20T14:34:00Z" }
    variants << message.deep_dup.tap { |m| m["payload"]["status"] = "missed" }
    variants.each { |invalid| expect { described_class.call(invalid) }.to raise_error(described_class::InvalidMessage) }
    expect(Call.count).to eq(0)
    expect(ProcessedMessage.count).to eq(0)
  end

  it "rolls back the call when saving the message fails" do
    allow_any_instance_of(ProcessedMessage).to receive(:save!).and_raise(ActiveRecord::StatementInvalid, "failure")
    expect { described_class.call(message) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(Call.count).to eq(0)
    expect(ProcessedMessage.count).to eq(0)
  end
end

RSpec.describe "concurrent call processing" do
  self.use_transactional_tests = false

  before { ProcessedMessage.delete_all; Call.delete_all }
  after { ProcessedMessage.delete_all; Call.delete_all }

  it "resolves races for the same message and for distinct messages of the same call" do
    base = JSON.parse(File.read(Rails.root.join("contracts/call.completed.v1.example.json")))
    messages = Array.new(2) { base.deep_dup } + Array.new(2) { base.deep_dup.tap { |m| m["messageId"] = SecureRandom.uuid } }
    ready = Queue.new
    start = Queue.new
    threads = messages.map do |message|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          CallCompletedProcessor.call(message)
        end
      end
    end
    messages.size.times { ready.pop }
    messages.size.times { start << true }
    results = threads.map(&:value)
    expect(results.count(:processed)).to eq(3)
    expect(results.count(:duplicate)).to eq(1)
    expect(Call.count).to eq(1)
    expect(ProcessedMessage.count).to eq(3)
  end
end
