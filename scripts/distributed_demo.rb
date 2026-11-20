require_relative "local_sqs_support"
require "securerandom"
require "timeout"

# Run only against disposable local queues; the unique calls are removed afterwards.
client, endpoint = LocalSqs.client_and_endpoint
token = SecureRandom.hex(8)
name = "auditoria-demo-#{token}"
dlq = "#{name}-dlq"
url = ->(n) { "#{endpoint}/000000000000/#{n}" }
queue = url.call(name)
body = JSON.parse(File.read(Rails.root.join("contracts/call.completed.v1.example.json")))
call_ids = []
make_body = lambda do
  event = Marshal.load(Marshal.dump(body))
  event["messageId"] = SecureRandom.uuid
  event["payload"]["callId"] = "demo-#{token}-#{SecureRandom.hex(4)}"
  call_ids << event["payload"]["callId"]
  JSON.generate(event)
end
receive = -> { client.receive_message(queue_url: queue, wait_time_seconds: 1, visibility_timeout: 2).messages.first }
publish = ->(value) { client.send_message(queue_url: queue, message_body: value) }
consumer = -> { SqsConsumer.new(client: client, queue_url: queue, logger: Logger.new($stdout), visibility_timeout: 2) }
wait_for = lambda do |&block|
  Timeout.timeout(45) { loop { result = block.call; break result if result; sleep 0.2 } }
end

begin
  client.create_queue(queue_name: dlq)
  arn = client.get_queue_attributes(queue_url: url.call(dlq), attribute_names: ["QueueArn"]).attributes.fetch("QueueArn")
  client.create_queue(queue_name: name, attributes: { "VisibilityTimeout" => "2", "RedrivePolicy" => JSON.generate(deadLetterTargetArn: arn, maxReceiveCount: "2") })

  # F2: stop a real process after its INSERT, while the transaction is still open.
  event = make_body.call
  publish.call(event)
  message = wait_for.call { receive.call }
  reader, writer = IO.pipe
  ActiveRecord::Base.connection_pool.disconnect!
  pid = fork do
    reader.close
    ProcessedMessage.class_eval do
      alias_method :demo_original_save!, :save!
      define_method(:save!) do |**args|
        demo_original_save!(**args).tap { writer.write("inserted"); writer.flush; sleep 60 }
      end
    end
    consumer.call.process(message)
    exit! 1
  end
  writer.close
  Timeout.timeout(20) { raise "worker failed before insert" unless reader.read(8) == "inserted" }
  Process.kill("KILL", pid)
  Process.wait(pid)
  raise "uncommitted data survived" if Call.exists?(call_id: JSON.parse(event)["payload"]["callId"])
  consumer.call.process(wait_for.call { receive.call })
  raise "F2 failed" unless Call.where(call_id: JSON.parse(event)["payload"]["callId"]).count == 1
  puts "F2: rollback after process termination and redelivery: OK"

  # F3: five separate SQS messages with one contract identity.
  event = make_body.call
  5.times { publish.call(event) }
  5.times { consumer.call.process(wait_for.call { receive.call }) }
  raise "F3 failed" unless Call.where(call_id: JSON.parse(event)["payload"]["callId"]).count == 1 && ProcessedMessage.where(message_id: JSON.parse(event)["messageId"]).count == 1
  puts "F3: five publications, one call and one processed message: OK"

  # A failed delete leaves the committed message available for redelivery.
  event = make_body.call
  publish.call(event)
  message = wait_for.call { receive.call }
  broken_client = Object.new
  def broken_client.delete_message(**); raise IOError, "simulated delete failure"; end
  SqsConsumer.new(client: broken_client, queue_url: queue, logger: Logger.new($stdout)).process(message)
  consumer.call.process(wait_for.call { receive.call })
  raise "delete recovery failed" unless ProcessedMessage.where(message_id: JSON.parse(event)["messageId"]).count == 1
  puts "Delete failure after commit and redelivery: OK"

  event = make_body.call
  publish.call(event)
  message = wait_for.call { receive.call }
  database_config = ActiveRecord::Base.connection_db_config.configuration_hash
  ActiveRecord::Base.establish_connection(database_config.merge(host: "127.0.0.1", port: 1, connect_timeout: 1))
  consumer.call.process(message)
  ActiveRecord::Base.establish_connection(database_config)
  raise "database failure created a call" if Call.exists?(call_id: JSON.parse(event)["payload"]["callId"])
  consumer.call.process(wait_for.call { receive.call })
  raise "database recovery failed" unless ProcessedMessage.where(message_id: JSON.parse(event)["messageId"]).count == 1
  puts "Database connection failure and redelivery: OK"

  # F4: invalid content and a conflicting identity both reach the actual DLQ.
  conflict = JSON.parse(event)
  conflict["payload"]["caller"] = "conflict"
  ["invalid JSON", JSON.generate(conflict)].each do |invalid|
    publish.call(invalid)
    2.times { consumer.call.process(wait_for.call { receive.call }); sleep 2.2 }
    wait_for.call do
      receive.call # triggers redrive in the emulator
      client.receive_message(queue_url: url.call(dlq), wait_time_seconds: 1).messages.first
    end
  end
  puts "F4: invalid and conflicting messages reached DLQ: OK"

  # F8: independent processes contend for repeated messages on one real queue.
  events = Array.new(12) { make_body.call }
  events.each { |value| 2.times { publish.call(value) } }
  workers = 3.times.map do
    Process.spawn("bundle", "exec", "rails", "runner", "scripts/demo_worker.rb", name)
  end
  workers.each { |worker| _, status = Process.wait2(worker); raise "worker failed" unless status.success? }
  events.each do |value|
    parsed = JSON.parse(value)
    raise "F8 failed" unless Call.where(call_id: parsed["payload"]["callId"]).count == 1 && ProcessedMessage.where(message_id: parsed["messageId"]).count == 1
  end
  puts "F8: three consumers, 24 deliveries, 12 calls and 12 processed messages: OK"
ensure
  ProcessedMessage.where(call_id: Call.where(call_id: call_ids).select(:id)).delete_all
  Call.where(call_id: call_ids).delete_all
  [name, dlq].each do |n|
    begin
      client.delete_queue(queue_url: url.call(n))
    rescue Aws::SQS::Errors::ServiceError
      warn "Could not remove temporary queue #{n}"
    end
  end
end
