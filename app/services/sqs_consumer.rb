require "aws-sdk-sqs"
require "json"

class SqsConsumer
  def initialize(client:, queue_url:, logger:)
    @client, @queue_url, @logger = client, queue_url, logger
    @stopping = false
  end

  def stop
    @stopping = true
  end

  def run
    @logger.info("SQS consumer started")
    until @stopping
      begin
        messages = @client.receive_message(queue_url: @queue_url, max_number_of_messages: 1,
          wait_time_seconds: 20, visibility_timeout: 120).messages
        messages.each { |message| process(message) } unless @stopping
      rescue StandardError => e
        @logger.error("SQS receive failed: #{e.class}")
        5.times { break if @stopping; sleep 1 }
      end
    end
    @logger.info("SQS consumer stopped")
  end

  def process(message)
    result = CallCompletedProcessor.call(message.body)
    @client.delete_message(queue_url: @queue_url, receipt_handle: message.receipt_handle)
    @logger.info("SQS message processed: sqs_id=#{message.message_id} result=#{result}")
  rescue StandardError => e
    # Do not log the payload, exception text, receipt handle, or connection settings.
    @logger.error("SQS message failed: sqs_id=#{message.message_id} error=#{e.class}")
  end
end
