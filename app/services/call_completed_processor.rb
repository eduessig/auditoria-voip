require "date"
require "digest"
require "json"
require "time"

class CallCompletedProcessor
  class InvalidMessage < StandardError; end
  class Conflict < StandardError; end

  ENVELOPE_KEYS = %w[messageId correlationId type version occurredAt payload].freeze
  PAYLOAD_KEYS = %w[callId caller callee startedAt answeredAt endedAt durationSeconds status].freeze
  REQUIRED_PAYLOAD_KEYS = (PAYLOAD_KEYS - ["answeredAt"]).freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  TIMESTAMP = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/

  def self.call(message)
    new(message).call
  end

  def initialize(message)
    @message = message.is_a?(String) ? JSON.parse(message) : message
  rescue JSON::ParserError => e
    raise InvalidMessage, "invalid JSON: #{e.message}"
  end

  def call
    validate!

    attempts = 0
    begin
      ApplicationRecord.transaction(requires_new: true) { persist! }
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      retry if attempts <= 2
      raise
    end
  end

  private

  def validate!
    object!(@message, ENVELOPE_KEYS, ENVELOPE_KEYS, "envelope")
    %w[messageId correlationId].each do |key|
      invalid!(key) unless @message[key].is_a?(String) && UUID.match?(@message[key])
    end
    invalid!("type") unless @message["type"] == "call.completed"
    invalid!("version") unless @message["version"].instance_of?(Integer) && @message["version"] == 1
    payload = @message["payload"]
    object!(payload, REQUIRED_PAYLOAD_KEYS, PAYLOAD_KEYS, "payload")
    %w[callId caller callee].each { |key| invalid!(key) unless payload[key].is_a?(String) && payload[key].match?(/\S/) }
    invalid!("durationSeconds") unless payload["durationSeconds"].instance_of?(Integer) && (0..2_147_483_647).cover?(payload["durationSeconds"])
    invalid!("status") unless Call::STATUSES.include?(payload["status"])
    answered = payload.key?("answeredAt")
    invalid!("answeredAt") unless (payload["status"] == "answered") == answered
    invalid!("durationSeconds") if !answered && payload["durationSeconds"] != 0
    @times = {}
    %w[startedAt endedAt].each { |key| @times[key] = timestamp!(payload[key], key) }
    @times["answeredAt"] = timestamp!(payload["answeredAt"], "answeredAt") if answered
    occurred = timestamp!(@message["occurredAt"], "occurredAt")
    invalid!("temporal order") if @times["startedAt"] > @times["endedAt"] || occurred < @times["endedAt"] ||
      (answered && !(@times["startedAt"]..@times["endedAt"]).cover?(@times["answeredAt"]))

    normalized_payload = payload.sort.to_h
    @times.each { |key, value| normalized_payload[key] = value.to_r.to_s }
    @call_fingerprint = fingerprint(normalized_payload)
    envelope = @message.sort.to_h.merge("messageId" => @message["messageId"].downcase,
      "correlationId" => @message["correlationId"].downcase, "occurredAt" => occurred.to_r.to_s,
      "payload" => normalized_payload)
    @envelope_fingerprint = fingerprint(envelope)
  end

  def object!(value, required, allowed, name)
    invalid!(name) unless value.is_a?(Hash) && (required - value.keys).empty? && (value.keys - allowed).empty?
  end

  def timestamp!(value, name)
    invalid!(name) unless value.is_a?(String) && TIMESTAMP.match?(value)
    parts = Date._iso8601(value)
    invalid!(name) unless Date.valid_date?(parts[:year], parts[:mon], parts[:mday]) &&
      (0..23).cover?(parts[:hour]) && (0..59).cover?(parts[:min]) && (0..59).cover?(parts[:sec]) &&
      parts[:offset] && parts[:offset].abs <= 86_340 && value[-2, 2].to_i <= 59
    Time.iso8601(value)
  rescue ArgumentError
    invalid!(name)
  end

  def invalid!(field)
    raise InvalidMessage, "invalid #{field}"
  end

  def fingerprint(value)
    Digest::SHA256.hexdigest(JSON.generate(value))
  end

  def persist!
    existing = ProcessedMessage.find_by(message_id: @message["messageId"])
    if existing
      raise Conflict, "messageId already used with different content" unless existing.envelope_fingerprint == @envelope_fingerprint
      return :duplicate
    end

    payload = @message["payload"]
    call = Call.find_by(call_id: payload["callId"])
    if call
      previous = call.processed_messages.first
      raise Conflict, "callId already used with different or unverifiable content" unless previous&.call_fingerprint == @call_fingerprint
    else
      call = Call.new(call_id: payload["callId"], caller: payload["caller"], callee: payload["callee"],
        started_at: @times["startedAt"], answered_at: @times["answeredAt"], ended_at: @times["endedAt"],
        duration_seconds: payload["durationSeconds"], status: payload["status"])
      call.save!(validate: false)
    end
    processed = ProcessedMessage.new(message_id: @message["messageId"], call: call, processed_at: Time.current,
      envelope_fingerprint: @envelope_fingerprint, call_fingerprint: @call_fingerprint)
    processed.save!(validate: false)
    :processed
  end
end
