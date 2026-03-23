#!/usr/bin/env bash
# Generate hardened inventories for CentOS Kafka lane from Azure resources.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <resource-group> <broker-admin-username> [control-node-username]" >&2
  exit 1
fi

RESOURCE_GROUP="$1"
BROKER_USER="$2"
CONTROL_USER="${3:-azureadmin}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INV_DIR="$BASE_DIR/inventory"

mkdir -p "$INV_DIR"

if ! az account show >/dev/null 2>&1; then
  echo "ERROR: Azure CLI not authenticated. Run 'az login' on control node." >&2
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH private key not found: $SSH_KEY" >&2
  exit 1
fi

# Discover only broker VMs created by terraform/centos (kafka-broker-0..N)
mapfile -t VM_NAMES < <(az vm list -g "$RESOURCE_GROUP" --query "[?starts_with(name, 'kafka-broker-')].name" -o tsv | sort)

if [[ ${#VM_NAMES[@]} -eq 0 ]]; then
  echo "ERROR: No broker VMs found in resource group $RESOURCE_GROUP" >&2
  exit 1
fi

# Build host records: vm_name|private_ip|public_ip|preferred_ssh_ip|node_id
HOST_RECORDS=()
INDEX=0
for VM in "${VM_NAMES[@]}"; do
  PRIVATE_IP=$(az vm list-ip-addresses -g "$RESOURCE_GROUP" -n "$VM" --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)
  PUBLIC_IP=$(az vm list-ip-addresses -g "$RESOURCE_GROUP" -n "$VM" --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv)

  if [[ -z "$PRIVATE_IP" || "$PRIVATE_IP" == "null" ]]; then
    echo "ERROR: Missing private IP for VM $VM" >&2
    exit 1
  fi

  if [[ "$PUBLIC_IP" == "null" ]]; then
    PUBLIC_IP=""
  fi

  # Prefer private IP for SSH from control node; fallback to public if needed.
  PREFERRED_SSH_IP="$PRIVATE_IP"
  if ! timeout 8 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i "$SSH_KEY" "$BROKER_USER@$PREFERRED_SSH_IP" "echo SSH_OK" >/dev/null 2>&1; then
    if [[ -n "$PUBLIC_IP" ]] && timeout 8 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i "$SSH_KEY" "$BROKER_USER@$PUBLIC_IP" "echo SSH_OK" >/dev/null 2>&1; then
      PREFERRED_SSH_IP="$PUBLIC_IP"
    fi
  fi

  NODE_ID=$((INDEX + 1))
  HOST_RECORDS+=("$VM|$PRIVATE_IP|$PUBLIC_IP|$PREFERRED_SSH_IP|$NODE_ID")
  INDEX=$((INDEX + 1))
done

# SSH readiness hardening check before Ansible runs.
for REC in "${HOST_RECORDS[@]}"; do
  VM_NAME="${REC%%|*}"
  REST="${REC#*|}"
  PRIVATE_IP="${REST%%|*}"
  REST="${REST#*|}"
  PUBLIC_IP="${REST%%|*}"
  REST="${REST#*|}"
  PREFERRED_SSH_IP="${REST%%|*}"

  echo "[check] SSH readiness for $VM_NAME (prefer private: $PRIVATE_IP, selected: $PREFERRED_SSH_IP)"
  READY=0
  for TRY in $(seq 1 24); do
    if timeout 15 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes -i "$SSH_KEY" "$BROKER_USER@$PREFERRED_SSH_IP" "echo SSH_OK" >/dev/null 2>&1; then
      READY=1
      break
    fi
    sleep 10
  done

  if [[ $READY -ne 1 ]]; then
    echo "ERROR: SSH not ready for $VM_NAME (private=$PRIVATE_IP public=${PUBLIC_IP:-none})" >&2
    exit 1
  fi

  # Basic cloud-init completion check (best-effort)
  timeout 15 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes -i "$SSH_KEY" "$BROKER_USER@$PREFERRED_SSH_IP" "test -f /var/log/kafka-bootstrap-complete.log" >/dev/null 2>&1 || true

done

KAFKA_INV="$INV_DIR/kafka_hosts"
MON_INV="$INV_DIR/inventory.ini"

{
  echo "[kafka]"
  for REC in "${HOST_RECORDS[@]}"; do
    VM_NAME="${REC%%|*}"
    REST="${REC#*|}"
    PRIVATE_IP="${REST%%|*}"
    REST="${REST#*|}"
    PUBLIC_IP="${REST%%|*}"
    REST="${REST#*|}"
    PREFERRED_SSH_IP="${REST%%|*}"
    NODE_ID="${REC##*|}"
    echo "$VM_NAME ansible_host=$PREFERRED_SSH_IP private_ip=$PRIVATE_IP public_ip=$PUBLIC_IP kafka_node_id=$NODE_ID"
  done
  echo
  echo "[all:vars]"
  echo "ansible_user=$BROKER_USER"
  echo "ansible_ssh_private_key_file=$SSH_KEY"
  # Use CentOS 7 default path. deploy_centos_cluster.sh also bootstraps python3.
  echo "ansible_python_interpreter=/usr/bin/python"
} > "$KAFKA_INV"

{
  echo "[management_node]"
  echo "localhost ansible_connection=local ansible_user=$CONTROL_USER"
  echo
  echo "[kafka_broker]"
  for REC in "${HOST_RECORDS[@]}"; do
    VM_NAME="${REC%%|*}"
    REST="${REC#*|}"
    PRIVATE_IP="${REST%%|*}"
    REST="${REST#*|}"
    PUBLIC_IP="${REST%%|*}"
    REST="${REST#*|}"
    PREFERRED_SSH_IP="${REST%%|*}"
    echo "$VM_NAME ansible_host=$PREFERRED_SSH_IP ansible_user=$BROKER_USER private_ip=$PRIVATE_IP public_ip=$PUBLIC_IP"
  done
  echo
  echo "[kafka_broker:vars]"
  echo "ansible_python_interpreter=/usr/bin/python"
} > "$MON_INV"

echo "Generated: $KAFKA_INV"
echo "Generated: $MON_INV"
