require "logger"
require "aws-sdk-sqs"

$stdout.sync = true
options = { region: ENV.fetch("AWS_REGION") }
options[:endpoint] = ENV.fetch("SQS_ENDPOINT") if ENV.key?("SQS_ENDPOINT") && !ENV["SQS_ENDPOINT"].empty?
options[:http_read_timeout] = 30
client = Aws::SQS::Client.new(**options)
consumer = SqsConsumer.new(client: client, queue_url: ENV.fetch("SQS_QUEUE_URL"), logger: Logger.new($stdout))
%w[INT TERM].each { |signal| Signal.trap(signal) { consumer.stop } }
consumer.run
