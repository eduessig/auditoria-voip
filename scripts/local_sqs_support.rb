require "aws-sdk-sqs"
require "json"
require "uri"

module LocalSqs
  def self.client_and_endpoint
    endpoint = URI.parse(ENV.fetch("SQS_ENDPOINT"))
    unless endpoint.scheme == "http" && %w[localhost 127.0.0.1 ::1 ministack].include?(endpoint.host) &&
        endpoint.userinfo.nil? && endpoint.path.to_s.empty? && endpoint.query.nil? && endpoint.fragment.nil?
      abort "SQS_ENDPOINT must be an explicit local HTTP endpoint without a path"
    end
    client = Aws::SQS::Client.new(endpoint: endpoint.to_s, region: ENV.fetch("AWS_REGION", "us-east-1"),
      credentials: Aws::Credentials.new("test", "test"))
    [client, endpoint]
  end
end
