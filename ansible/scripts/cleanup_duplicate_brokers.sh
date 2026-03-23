#!/bin/bash
# cleanup_duplicate_brokers.sh
# Emergency script to remove conflicting Kafka broker VMs from Azure
# WARNING: This will DELETE the specified brokers - use with caution!
# Usage: ./cleanup_duplicate_brokers.sh [--subscription-id <id>] [--resource-group <rg>] [--vm-prefix <prefix>] [--broker-indices 4,5]

set -e

SUBSCRIPTION_ID=""
RESOURCE_GROUP="${KAFKA_RESOURCE_GROUP:-kafka-cluster}"
VM_PREFIX="${KAFKA_VM_PREFIX:-kafka-cluster}"
BROKER_INDICES=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --subscription-id) SUBSCRIPTION_ID="$2"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --vm-prefix) VM_PREFIX="$2"; shift 2 ;;
    --broker-indices) BROKER_INDICES="$2"; shift 2 ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$SUBSCRIPTION_ID" ]]; then
  log_error "subscription-id is required: --subscription-id <id>"
  exit 1
fi

if [[ -z "$BROKER_INDICES" ]]; then
  log_error "broker-indices is required: --broker-indices 4,5 (comma-separated indices)"
  exit 1
fi

log_warn "⚠️  WARNING: This script will DELETE the specified broker VMs!"
log_warn "Resource Group: $RESOURCE_GROUP"
log_warn "Broker Indices: $BROKER_INDICES"
echo ""
read -p "Type 'DELETE' to confirm deletion: " CONFIRM
if [[ "$CONFIRM" != "DELETE" ]]; then
  log_info "Cancelled"
  exit 0
fi

# Set Azure context
az account set --subscription "$SUBSCRIPTION_ID" || {
  log_error "Failed to set subscription context"
  exit 1
}

# Parse broker indices
IFS=',' read -ra INDICES <<< "$BROKER_INDICES"

for i in "${INDICES[@]}"; do
  VM_NAME="${VM_PREFIX}-broker-$i"
  NIC_NAME="${VM_PREFIX}-nic-$i"
  DISK_NAME="kafka-data-disk-$i"
  
  # Delete VM
  if az vm show --name "$VM_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    log_info "Deleting VM: $VM_NAME..."
    az vm delete --name "$VM_NAME" --resource-group "$RESOURCE_GROUP" --yes &>/dev/null
    log_success "Deleted $VM_NAME"
  else
    log_warn "VM $VM_NAME not found, skipping"
  fi
  
  # Delete NIC
  if az network nic show --name "$NIC_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    log_info "Deleting NIC: $NIC_NAME..."
    az network nic delete --name "$NIC_NAME" --resource-group "$RESOURCE_GROUP" --yes &>/dev/null
    log_success "Deleted $NIC_NAME"
  fi
  
  # Delete data disk
  if az disk show --name "$DISK_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    log_info "Deleting disk: $DISK_NAME..."
    az disk delete --name "$DISK_NAME" --resource-group "$RESOURCE_GROUP" --yes &>/dev/null
    log_success "Deleted $DISK_NAME"
  fi
done

echo ""
log_success "Cleanup complete!"
echo ""
echo "Next steps:"
echo "1. Run: terraform apply -auto-approve (to recreate the brokers)"
echo ""
