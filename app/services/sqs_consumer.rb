require "aws-sdk-sqs"
require "json"

class SqsConsumer
  def initialize(client:, queue_url:, logger:, health: nil, visibility_timeout: 120, random: Random.new)
    @client, @queue_url, @logger = client, queue_url, logger
    @health = health
    @visibility_timeout, @random = visibility_timeout, random
    @stopping = false
  end

  def stop
    @stopping = true
  end

  def run
    @logger.info("SQS consumer started")
    failures = 0
    until @stopping
      begin
        @health&.cycle
        messages = @client.receive_message(queue_url: @queue_url, max_number_of_messages: 1,
          wait_time_seconds: 20, visibility_timeout: @visibility_timeout).messages
        @health&.queue_success
        failures = 0
        messages.each { |message| process(message) } unless @stopping
      rescue StandardError => e
        @health&.queue_failure
        @logger.error("SQS receive failed: #{e.class}")
        failures += 1
        delay = @random.rand * [2**[failures - 1, 5].min, 30].min
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + delay
        until @stopping || (remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)) <= 0
          sleep [remaining, 0.25].min
        end
      end
    end
    @logger.info("SQS consumer stopped")
  end

  def process(message)
    result = CallCompletedProcessor.call(message.body)
    @client.delete_message(queue_url: @queue_url, receipt_handle: message.receipt_handle)
    @logger.info("SQS message processed: sqs_id=#{message.message_id} result=#{result}")
  rescue StandardError => e
    @logger.error("SQS message failed: sqs_id=#{message.message_id} error=#{e.class}")
  end
end
