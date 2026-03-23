#!/bin/bash
# Quick test script to verify SSH connectivity to all brokers

BROKERS=(
  "172.16.1.5"
  "172.16.1.4"
  "172.16.1.6"
  "172.16.1.7"
)

echo "Testing SSH connectivity to all Kafka brokers..."
echo ""

for broker_ip in "${BROKERS[@]}"; do
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new rockyadmin@"$broker_ip" 'echo OK' &>/dev/null 2>&1; then
    echo "✅ $broker_ip: SSH OK"
  else
    echo "⚠️  $broker_ip: SSH FAILED"
  fi
done

echo ""
echo "All brokers should show ✅ SSH OK for health checks to pass."
