require "rails_helper"

RSpec.describe "Calls API", type: :request do
  let(:body) { JSON.parse(response.body) }
  let(:example_event) { JSON.parse(File.read(Rails.root.join("contracts/call.completed.v1.example.json"))) }

  def create_call(id, caller, callee, status, started_at)
    Call.create!(call_id: id, caller: caller, callee: callee, status: status,
      started_at: started_at, ended_at: started_at + 60, answered_at: status == "answered" ? started_at : nil,
      duration_seconds: status == "answered" ? 60 : 0)
  end

  it "lists filtered calls with stable pagination and UTC timestamps" do
    start = Time.iso8601("2026-11-20T10:00:00Z")
    create_call("a", "1001", "1002", "answered", start)
    create_call("b", "1001", "1002", "answered", start + 60)
    create_call("c", "1001", "1003", "missed", start + 120)
    get "/api/v1/calls", params: { caller: "1001", callee: "1002", status: "answered", started_at_from: "2026-11-20T07:00:00-03:00", started_at_to: "2026-11-20T10:01:00Z", page: 2, per_page: 1 }
    expect(response).to have_http_status(:ok)
    expect(body["data"].map { |call| call["call_id"] }).to eq(["a"])
    expect(body["data"].first["started_at"]).to eq("2026-11-20T10:00:00.000000Z")
    expect(body["pagination"]).to eq("page" => 2, "per_page" => 1, "total" => 2, "total_pages" => 2)
  end

  it "returns a processed queue message by its contract call ID" do
    client = Aws::SQS::Client.new(stub_responses: true, region: "us-east-1")
    message = Aws::SQS::Types::Message.new(message_id: "sqs-id", receipt_handle: "receipt", body: example_event.to_json)
    SqsConsumer.new(client: client, queue_url: "http://localhost/queue", logger: Logger.new(StringIO.new)).process(message)
    get "/api/v1/calls/#{example_event['payload']['callId']}"
    expect(response).to have_http_status(:ok)
    expect(body.dig("data", "call_id")).to eq(example_event["payload"]["callId"])
  end

  it "returns 404 for an unknown call" do
    get "/api/v1/calls/missing"
    expect(response).to have_http_status(:not_found)
    expect(body.dig("error", "code")).to eq("not_found")
  end

  it "rejects invalid query parameters" do
    [{ page: "0" }, { per_page: "101" }, { caller: "" }, { status: "other" },
     { started_at_from: "2026-11-20" }, { started_at_to: "invalid" },
     { started_at_from: "2026-11-21T00:00:00Z", started_at_to: "2026-11-20T00:00:00Z" },
     { unexpected: "x" }, { page: ["1"] }].each do |query|
      get "/api/v1/calls", params: query
      expect(response).to have_http_status(:bad_request), "#{query.inspect} returned #{response.status}"
      expect(body.dig("error", "code")).to eq("invalid_parameters")
    end
  end

  it "checks PostgreSQL in the API health endpoint" do
    get "/health"
    expect(response).to have_http_status(:ok)
    allow(ActiveRecord::Base.connection_pool).to receive(:with_connection).and_raise(ActiveRecord::ConnectionNotEstablished)
    get "/health"
    expect(response).to have_http_status(:service_unavailable)
    expect(body["database"]).to eq("unavailable")
  end
end
