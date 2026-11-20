require "logger"
require "aws-sdk-sqs"

$stdout.sync = true
options = { region: ENV.fetch("AWS_REGION") }
options[:endpoint] = ENV.fetch("SQS_ENDPOINT") if ENV.key?("SQS_ENDPOINT") && !ENV["SQS_ENDPOINT"].empty?
options[:http_read_timeout] = 30
options[:http_open_timeout] = 5
options[:retry_limit] = 0
client = Aws::SQS::Client.new(**options)
health = ConsumerHealth.new(ENV.fetch("CONSUMER_HEALTH_PATH", "/tmp/auditoria-consumer-health.json"))
visibility = Integer(ENV.fetch("SQS_VISIBILITY_TIMEOUT", "120"), 10)
abort "SQS_VISIBILITY_TIMEOUT must be between 1 and 43200" unless (1..43_200).cover?(visibility)
consumer = SqsConsumer.new(client: client, queue_url: ENV.fetch("SQS_QUEUE_URL"), logger: Logger.new($stdout), health: health, visibility_timeout: visibility)
%w[INT TERM].each { |signal| Signal.trap(signal) { consumer.stop } }
consumer.run
