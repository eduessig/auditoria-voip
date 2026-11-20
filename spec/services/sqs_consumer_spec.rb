require "rails_helper"
require "aws-sdk-sqs"
require "stringio"

RSpec.describe SqsConsumer do
  let(:client) { Aws::SQS::Client.new(stub_responses: true, region: "us-east-1") }
  let(:queue_url) { "http://localhost:4566/000000000000/calls" }
  let(:consumer) { described_class.new(client: client, queue_url: queue_url, logger: Logger.new(StringIO.new)) }
  let(:body) { File.read(Rails.root.join("contracts/call.completed.v1.example.json")) }
  let(:message) { Aws::SQS::Types::Message.new(message_id: "sqs-id", receipt_handle: "receipt", body: body) }

  it "deletes only after a successful commit, including equivalent redelivery" do
    2.times { consumer.process(message) }
    expect(Call.count).to eq(1)
    expect(ProcessedMessage.count).to eq(1)
    expect(client.api_requests.count { |r| r[:operation_name] == :delete_message }).to eq(2)
  end

  it "leaves invalid messages and processing failures in the queue" do
    message.body = "invalid"
    consumer.process(message)
    message.body = body
    allow(CallCompletedProcessor).to receive(:call).and_raise(ActiveRecord::StatementInvalid)
    consumer.process(message)
    expect(client.api_requests).to be_empty
    expect(Call.count).to eq(0)
  end

  it "keeps the committed effect when deletion fails and accepts redelivery" do
    client.stub_responses(:delete_message, ["ServiceUnavailable", {}])
    consumer.process(message)
    consumer.process(message)
    expect(Call.count).to eq(1)
    expect(ProcessedMessage.count).to eq(1)
    expect(client.api_requests.count { |r| r[:operation_name] == :delete_message }).to eq(2)
  end
end
