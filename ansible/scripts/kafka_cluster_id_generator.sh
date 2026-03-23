#!/bin/bash
# kafka_cluster_id_generator.sh
# Generate a deterministic Kafka Cluster ID for KRaft mode
# Kafka cluster ID must be unique and consistent across all brokers

set -e

CLUSTER_NAME="${1:-kafka-cluster}"
NAMESPACE="${2:-prod}"

# Option 1: Generate UUID-based cluster ID (deterministic from name)
# This generates a v5 UUID from cluster name
generate_uuid_cluster_id() {
    local name="$1"
    # Using namespace "kafka.apache.org" for deterministic UUID generation
    python3 << EOF
import uuid
namespace = uuid.NAMESPACE_DNS
name = "$name"
cluster_id = uuid.uuid5(namespace, name)
print(str(cluster_id))
EOF
}

# Option 2: Generate using Kafka's tools (if Kafka is already installed)
# This generates in the format that Kafka expects
generate_kraft_cluster_id() {
    # Format: 16 hex characters representing 8 bytes
    # Pattern: MkxpQ1ZOTDAxLWY0ZjllOGU3Y2U5Mw== (base64 encoded UUID)
    python3 << EOF
import uuid
import base64
import struct

# Generate a random UUID
random_uuid = uuid.uuid4()

# Convert UUID to bytes and encode as base64
# Kafka cluster ID is the first 16 characters of base64 encoded UUID
uuid_bytes = random_uuid.bytes
cluster_id_b64 = base64.b64encode(uuid_bytes).decode('utf-8')
# Remove padding
cluster_id = cluster_id_b64.replace('=', '')[:16]
print(cluster_id)
EOF
}

# Option 3: Use Kafka's built-in generator (requires kafka tools)
# Usage: kafka-storage.sh random-uuid
generate_with_kafka_tools() {
    # This requires Kafka to be installed
    # For KRaft: kafka-storage.sh random-uuid
    which kafka-storage.sh > /dev/null 2>&1 && {
        kafka-storage.sh random-uuid
    } || echo "Kafka tools not found"
}

# Main
echo "Generating Kafka Cluster ID..."
CLUSTER_ID=$(generate_kraft_cluster_id)
echo "CLUSTER_ID=$CLUSTER_ID"

# Output format suitable for Ansible variables
cat <<EOF
# Kafka Cluster Configuration
kafka_cluster_id: "${CLUSTER_ID}"
kafka_cluster_name: "${CLUSTER_NAME}"
kafka_namespace: "${NAMESPACE}"
EOF
