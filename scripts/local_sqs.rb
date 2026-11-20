require_relative "local_sqs_support"

# Only known local addresses are accepted; never discover credentials from the environment.
client, endpoint = LocalSqs.client_and_endpoint
name = ENV.fetch("SQS_QUEUE_NAME", "auditoria-calls")
abort "Invalid queue name" unless /\A[a-zA-Z0-9_-]{1,76}\z/.match?(name)

# Construct URLs using the validated endpoint, not a URL returned by the emulator.
queue_url = ->(queue_name) { "#{endpoint}/000000000000/#{queue_name}" }
case ARGV.fetch(0, "")
when "setup"
  dlq = "#{name}-dlq"
  client.create_queue(queue_name: dlq)
  arn = client.get_queue_attributes(queue_url: queue_url.call(dlq), attribute_names: ["QueueArn"]).attributes.fetch("QueueArn")
  attributes = { "VisibilityTimeout" => "120", "ReceiveMessageWaitTimeSeconds" => "20",
    "RedrivePolicy" => JSON.generate(deadLetterTargetArn: arn, maxReceiveCount: "5") }
  client.create_queue(queue_name: name, attributes: attributes)
  puts "Local queues ready: #{name}, #{dlq}"
when "publish"
  path = ARGV[1] || "contracts/call.completed.v1.example.json"
  client.send_message(queue_url: queue_url.call(name), message_body: File.read(path))
  puts "Example published to #{name}"
else
  abort "Usage: ruby scripts/local_sqs.rb setup|publish [example.json]"
end
