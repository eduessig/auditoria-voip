#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
project="auditoria-demo-$(date +%s)-$$"
compose=(docker compose -p "$project" -f compose.yaml -f compose.demo.yaml)
cleanup() { "${compose[@]}" down -v --remove-orphans; }
trap cleanup EXIT

"${compose[@]}" up -d db ministack db-setup sqs-setup consumer
"${compose[@]}" stop ministack
sleep 25
"${compose[@]}" logs consumer | grep -q 'SQS receive failed'
"${compose[@]}" up -d --wait ministack
"${compose[@]}" run --rm --no-deps sqs-setup bundle exec ruby scripts/local_sqs.rb setup
"${compose[@]}" run --rm --no-deps sqs-setup bundle exec ruby scripts/local_sqs.rb publish
for attempt in $(seq 1 45); do
  count=$("${compose[@]}" exec -T db psql -U "${DATABASE_USER:-auditoria}" -d auditoria_development -Atc "SELECT count(*) FROM calls WHERE call_id = 'call-20261120-001'" | tr -d '[:space:]')
  if [ "$count" = 1 ]; then
    "${compose[@]}" logs consumer | grep 'SQS message processed'
    echo 'F6: broker stopped and restarted; consumer recovered automatically and persisted one call: OK'
    exit 0
  fi
  sleep 2
done
echo 'F6: timed out waiting for recovery' >&2
exit 1
