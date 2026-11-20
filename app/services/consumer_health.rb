require "json"
require "time"
require "tempfile"

class ConsumerHealth
  MAX_AGE = 90

  def initialize(path)
    @path = path
    @state = { pid: Process.pid, cycle_at: nil, queue_at: nil, queue: "unknown" }
  end

  def cycle
    @state[:cycle_at] = Time.now.utc.iso8601(6)
    write
  end

  def queue_success
    @state[:queue] = "ok"
    @state[:queue_at] = Time.now.utc.iso8601(6)
    write
  end

  def queue_failure
    @state[:queue] = "unavailable"
    write
  end

  def self.check(path, now: Time.now)
    state = JSON.parse(File.read(path))
    pid = Integer(state.fetch("pid"))
    raise ArgumentError unless pid.positive?
    Process.kill(0, pid)
    fresh = ->(value) { value && (age = now - Time.iso8601(value)) >= 0 && age <= MAX_AGE }
    { process: "active", cycle: fresh.call(state["cycle_at"]) ? "advancing" : "stale",
      queue: state["queue"] == "ok" && fresh.call(state["queue_at"]) ? "ok" : "unavailable" }
  rescue Errno::ESRCH, Errno::ENOENT, JSON::ParserError, KeyError, ArgumentError, TypeError
    { process: "unavailable", cycle: "unknown", queue: "unknown" }
  end

  private

  def write
    Tempfile.create("consumer-health", File.dirname(@path)) do |file|
      file.write(JSON.generate(@state))
      file.flush
      File.rename(file.path, @path)
    end
  end
end
