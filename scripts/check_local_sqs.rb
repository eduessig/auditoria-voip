require_relative "local_sqs_support"
require "securerandom"

client, endpoint = LocalSqs.client_and_endpoint
name = "auditoria-check-#{SecureRandom.hex(8)}"
dlq = "#{name}-dlq"
url = ->(n) { "#{endpoint}/000000000000/#{n}" }
begin
  client.create_queue(queue_name: dlq)
  arn = client.get_queue_attributes(queue_url: url.call(dlq), attribute_names: ["QueueArn"]).attributes.fetch("QueueArn")
  client.create_queue(queue_name: name, attributes: { "VisibilityTimeout" => "1",
    "RedrivePolicy" => JSON.generate(deadLetterTargetArn: arn, maxReceiveCount: "2") })
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  raise "long polling returned too early" unless client.receive_message(queue_url: url.call(name), wait_time_seconds: 1).messages.empty? &&
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start >= 0.8
  client.send_message(queue_url: url.call(name), message_body: "local check")
  raise "first receive failed" unless client.receive_message(queue_url: url.call(name)).messages.size == 1
  raise "visibility failed" unless client.receive_message(queue_url: url.call(name)).messages.empty?
  sleep 1.2
  raise "redelivery failed" unless client.receive_message(queue_url: url.call(name)).messages.size == 1
  sleep 1.2
  client.receive_message(queue_url: url.call(name))
  raise "DLQ redrive failed" unless client.receive_message(queue_url: url.call(dlq)).messages.size == 1
  puts "Long polling, visibility, redelivery and DLQ redrive passed"
ensure
  [name, dlq].each do |queue|
    begin
      client.delete_queue(queue_url: url.call(queue))
    rescue Aws::SQS::Errors::NonExistentQueue
    end
  end
end
