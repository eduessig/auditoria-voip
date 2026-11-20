require_relative "local_sqs_support"
client, endpoint = LocalSqs.client_and_endpoint
name = ARGV.fetch(0)
abort "Invalid demo queue" unless /\Aauditoria-demo-[0-9a-f]{16}\z/.match?(name)
queue = "#{endpoint}/000000000000/#{name}"
worker = SqsConsumer.new(client: client, queue_url: queue, logger: Logger.new($stdout), visibility_timeout: 10)
loop do
  messages = client.receive_message(queue_url: queue, wait_time_seconds: 2, max_number_of_messages: 1).messages
  break if messages.empty?
  messages.each { |message| worker.process(message) }
end
