#!/bin/bash
# import_existing_brokers.sh
# Helper script to import existing Kafka broker resources into Terraform state
# Moved to ansible/scripts/ but runs terraform from terraform/kafka directory
# Usage: ./import_existing_brokers.sh [--subscription-id <id>] [--resource-group kafka_t1] [--broker-count 6]

set -e

SUBSCRIPTION_ID=""
RESOURCE_GROUP="${KAFKA_RESOURCE_GROUP:-kafka-cluster}"
BROKER_COUNT=6

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
    --broker-count) BROKER_COUNT="$2"; shift 2 ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$SUBSCRIPTION_ID" ]]; then
  log_error "subscription-id is required: --subscription-id <id>"
  exit 1
fi

log_info "Importing existing Kafka broker resources into Terraform state"
log_info "Subscription ID: $SUBSCRIPTION_ID"
log_info "Resource Group: $RESOURCE_GROUP"
log_info "Broker Count: $BROKER_COUNT"
echo ""

# Set Azure context
az account set --subscription "$SUBSCRIPTION_ID" || {
  log_error "Failed to set subscription context"
  exit 1
}

# Find terraform directory relative to this script's location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/../../terraform/kafka" && pwd)"

log_info "Terraform working directory: $TERRAFORM_DIR"
cd "$TERRAFORM_DIR"

# Export subscription ID as environment variable for Terraform
export TF_VAR_ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"

# Initialize Terraform if needed
if [[ ! -d ".terraform" ]]; then
  log_info "Initializing Terraform..."
  terraform init -upgrade >/dev/null 2>&1
fi

# Import VM resources
VM_PREFIX="${KAFKA_VM_PREFIX:-kafka-cluster}"
for ((i=0; i<BROKER_COUNT; i++)); do
  VM_NAME="${VM_PREFIX}-broker-$i"
  VM_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$VM_NAME"
  
  # Check if VM exists in Azure
  if az vm show --name "$VM_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    log_info "Checking if $VM_NAME exists in Terraform state..."
    
    # Try to import - if already in state, this will fail gracefully
    if terraform import -var="ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID" azurerm_linux_virtual_machine.kafka_brokers[$i] "$VM_ID" 2>&1 | grep -q "already managed"; then
      log_warn "$VM_NAME already in Terraform state, skipping"
    elif terraform import -var="ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID" azurerm_linux_virtual_machine.kafka_brokers[$i] "$VM_ID" 2>&1; then
      log_success "Imported $VM_NAME into Terraform state"
    else
      log_warn "Could not import $VM_NAME (may already be in state)"
    fi
  else
    log_warn "VM $VM_NAME does not exist in Azure, skipping"
  fi
done

echo ""
log_success "Import complete!"
echo ""
echo "Next steps:"
echo "1. Verify imported resources: terraform state list | grep kafka_brokers"
echo "2. Review Terraform plan: terraform plan -out=tfplan"
echo "3. Apply changes: terraform apply tfplan"
echo ""
