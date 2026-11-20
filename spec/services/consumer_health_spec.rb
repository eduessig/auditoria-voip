require "rails_helper"
require "tmpdir"

RSpec.describe ConsumerHealth do
  it "distinguishes process, cycle progress, and queue connectivity" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "health.json")
      expect(described_class.check(path)[:process]).to eq("unavailable")
      health = described_class.new(path)
      health.cycle
      expect(described_class.check(path)).to eq(process: "active", cycle: "advancing", queue: "unavailable")
      health.queue_success
      expect(described_class.check(path)).to eq(process: "active", cycle: "advancing", queue: "ok")
      expect(described_class.check(path, now: Time.now + 91)).to eq(process: "active", cycle: "stale", queue: "unavailable")
      health.queue_failure
      expect(described_class.check(path)[:queue]).to eq("unavailable")
    end
  end
end
