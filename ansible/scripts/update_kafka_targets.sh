#!/bin/bash
# Update Prometheus targets when Kafka cluster scales

set -euo pipefail

RESOURCE_GROUP="${1:-}"
KAFKA_EXPORTER_PORT="${2:-9308}"
NODE_EXPORTER_PORT="${3:-9100}"
TARGETS_DIR="/etc/prometheus/file_sd"

if [[ -z "$RESOURCE_GROUP" ]]; then
  echo "Error: resource group is required as first argument" >&2
  echo "Usage: $0 <resource-group> [kafka_exporter_port] [node_exporter_port]" >&2
  exit 1
fi

mkdir -p "$TARGETS_DIR"

# Get all Kafka broker VMs sorted by name
echo "Discovering Kafka brokers in resource group: $RESOURCE_GROUP"
vm_names=$(az vm list -g "$RESOURCE_GROUP" \
  --query "[?starts_with(name, '${KAFKA_VM_PREFIX}-broker-')].name" -o tsv | sort)

if [[ -z "$vm_names" ]]; then
    echo "Error: No Kafka brokers found" >&2
    exit 1
fi

# Generate Kafka exporter targets
echo "Generating kafka_targets.json..."
cat > "$TARGETS_DIR/kafka_targets.json" <<'EOF'
[
EOF

first=true
for vm_name in $vm_names; do
    private_ip=$(az vm list-ip-addresses -g "$RESOURCE_GROUP" -n "$vm_name" \
      --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)
    
    if [[ -z "$private_ip" || "$private_ip" == "null" ]]; then
        echo "Warning: Could not get IP for $vm_name" >&2
        continue
    fi

    if [[ "$first" == "true" ]]; then
        first=false
    else
        echo "," >> "$TARGETS_DIR/kafka_targets.json"
    fi

    cat >> "$TARGETS_DIR/kafka_targets.json" <<EOT
  {
    "targets": ["${private_ip}:${KAFKA_EXPORTER_PORT}"],
    "labels": {
      "job": "kafka-exporter",
      "instance": "${vm_name}"
    }
  }
EOT
done

echo "" >> "$TARGETS_DIR/kafka_targets.json"
echo "]" >> "$TARGETS_DIR/kafka_targets.json"

# Generate Node exporter targets
echo "Generating node_targets.json..."
cat > "$TARGETS_DIR/node_targets.json" <<'EOF'
[
EOF

first=true
for vm_name in $vm_names; do
    private_ip=$(az vm list-ip-addresses -g "$RESOURCE_GROUP" -n "$vm_name" \
      --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)
    
    if [[ -z "$private_ip" || "$private_ip" == "null" ]]; then
        continue
    fi

    if [[ "$first" == "true" ]]; then
        first=false
    else
        echo "," >> "$TARGETS_DIR/node_targets.json"
    fi

    cat >> "$TARGETS_DIR/node_targets.json" <<EOT
  {
    "targets": ["${private_ip}:${NODE_EXPORTER_PORT}"],
    "labels": {
      "job": "node-exporter",
      "instance": "${vm_name}"
    }
  }
EOT
done

echo "" >> "$TARGETS_DIR/node_targets.json"
echo "]" >> "$TARGETS_DIR/node_targets.json"

echo "Targets updated successfully:"
echo "- Kafka targets: $TARGETS_DIR/kafka_targets.json"
echo "- Node targets: $TARGETS_DIR/node_targets.json"
echo "Prometheus will reload in 30 seconds"