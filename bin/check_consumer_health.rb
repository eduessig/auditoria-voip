require_relative "../app/services/consumer_health"

result = ConsumerHealth.check(ENV.fetch("CONSUMER_HEALTH_PATH", "/tmp/auditoria-consumer-health.json"))
puts JSON.generate(result)
exit(result == { process: "active", cycle: "advancing", queue: "ok" } ? 0 : 1)
