#!/bin/bash
# scale_out_broker.sh
# Comprehensive shell wrapper for scaling out Kafka cluster by provisioning and configuring brokers
# Usage:
#   Single broker: ./scale_out_broker.sh --broker-name kafka-broker-3 --subscription-id <id> --resource-group <rg>
#   Multiple brokers: ./scale_out_broker.sh --broker-count 6 --subscription-id <id> --resource-group <rg>
#   (--broker-count: total desired broker count, script calculates which brokers to add)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../.."
TERRAFORM_DIR="${PROJECT_ROOT}/terraform/kafka"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/kafka_hosts"
REPO_NAME="$(basename "$PROJECT_ROOT")"

# Defaults
BROKER_NAME=""
BROKER_COUNT=""
NUM_BROKERS=""
CURRENT_BROKER_COUNT=0
SUBSCRIPTION_ID=""
RESOURCE_GROUP=""
AUTO_APPROVE=false
ANSIBLE_USER="rockyadmin"
SSH_KEY=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --broker-name) BROKER_NAME="$2"; shift 2 ;;
    --broker-count) BROKER_COUNT="$2"; shift 2 ;;
    --num-brokers) NUM_BROKERS="$2"; shift 2 ;;
    --subscription-id) SUBSCRIPTION_ID="$2"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --auto-approve) AUTO_APPROVE=true; shift ;;
    --ansible-user) ANSIBLE_USER="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate inputs
if [[ -z "$SUBSCRIPTION_ID" ]]; then
  log_error "subscription-id is required: --subscription-id <id>"
  exit 1
fi

if [[ -z "$RESOURCE_GROUP" ]]; then
  log_error "resource-group is required: --resource-group <name>"
  exit 1
fi

# Determine scaling mode and validate parameters
if [[ -n "$BROKER_COUNT" && -n "$BROKER_NAME" ]]; then
  log_error "Cannot specify both --broker-count and --broker-name. Use one or the other."
  exit 1
fi

# Get current broker count from inventory
if [[ -f "$INVENTORY_FILE" ]]; then
  # Count brokers with 0-indexed naming: kafka-broker-0, kafka-broker-1, etc.
  CURRENT_BROKER_COUNT=$(grep -c "^kafka-broker-" "$INVENTORY_FILE" || echo "0")
fi

# Mode 1: Single broker scale (--broker-name)
if [[ -n "$BROKER_NAME" ]]; then
  NUM_BROKERS=1
  BROKER_COUNT=$((CURRENT_BROKER_COUNT + 1))
  log_info "Single broker mode: Adding 1 broker ($BROKER_NAME)"
# Mode 2: Multi-broker scale (--broker-count)
elif [[ -n "$BROKER_COUNT" ]]; then
  if [[ $BROKER_COUNT -le $CURRENT_BROKER_COUNT ]]; then
    log_error "Target broker count ($BROKER_COUNT) must be greater than current count ($CURRENT_BROKER_COUNT)"
    exit 1
  fi
  NUM_BROKERS=$((BROKER_COUNT - CURRENT_BROKER_COUNT))
  log_info "Multi-broker mode: Adding $NUM_BROKERS brokers (scaling from $CURRENT_BROKER_COUNT to $BROKER_COUNT)"
else
  log_error "Must specify either --broker-name or --broker-count"
  exit 1
fi

# Auto-detect SSH key if not provided
if [[ -z "$SSH_KEY" ]]; then
  # Check common SSH key locations
  for key_path in ~/.ssh/id_rsa ~/.ssh/id_ed25519 ~/.ssh/id_ecdsa; do
    if [[ -f "$key_path" ]]; then
      SSH_KEY="$key_path"
      log_info "Auto-detected SSH key: $SSH_KEY"
      break
    fi
  done
fi

# Validate SSH key if provided
if [[ -n "$SSH_KEY" && ! -f "$SSH_KEY" ]]; then
  log_warn "SSH key not found: $SSH_KEY"
  SSH_KEY=""
fi

# Set Azure subscription context
log_info "Setting Azure subscription context..."
az account set --subscription "$SUBSCRIPTION_ID" || {
  log_error "Failed to set subscription context"
  exit 1
}

log_info "Kafka Cluster Scale-Out: Adding $NUM_BROKERS broker(s)"
log_info "Target Broker Count: $BROKER_COUNT"
log_info "Current Broker Count: $CURRENT_BROKER_COUNT"
log_info "Subscription ID: $SUBSCRIPTION_ID"
log_info "Resource Group: $RESOURCE_GROUP"
log_info "Ansible User: $ANSIBLE_USER"
echo ""

# Detect existing infrastructure configuration from Azure (if brokers exist)
KAFKA_VM_SIZE=""
KAFKA_LOCATION=""
KAFKA_ZONE=""
KAFKA_NAME_PREFIX=""
KAFKA_DISK_TYPE=""
USE_PREMIUM_V2="false"
IS_PUBLIC="false"
USE_EXISTING_NETWORK="false"
KAFKA_VNET_NAME=""
KAFKA_SUBNET_NAME=""
KAFKA_VNET_RG=""
KAFKA_NSG_ID=""

if [[ $CURRENT_BROKER_COUNT -gt 0 ]]; then
  log_info "Detecting existing infrastructure configuration from Azure..."
  RG_EXISTS=$(az group exists --name "$RESOURCE_GROUP" 2>/dev/null || echo "false")
  
  # Find first existing broker VM dynamically
  EXISTING_VM_NAME=$(az vm list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?contains(name, 'broker')].name | [0]" \
    --output tsv 2>/dev/null || echo "")
  
  if [[ -n "$EXISTING_VM_NAME" ]]; then
    log_info "Found existing broker VM: $EXISTING_VM_NAME"
    
    # Extract VM size
    KAFKA_VM_SIZE=$(az vm show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$EXISTING_VM_NAME" \
      --query "hardwareProfile.vmSize" \
      --output tsv 2>/dev/null || echo "")
    
    # Extract location
    KAFKA_LOCATION=$(az vm show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$EXISTING_VM_NAME" \
      --query "location" \
      --output tsv 2>/dev/null || echo "")
    
    # Extract zone (may be empty for non-zonal deployments)
    KAFKA_ZONE=$(az vm show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$EXISTING_VM_NAME" \
      --query "zones[0]" \
      --output tsv 2>/dev/null || echo "")
    
    # Extract name prefix (everything before "-broker-")
    KAFKA_NAME_PREFIX="${EXISTING_VM_NAME%%-broker-*}"
    
    # Check if existing VMs have public IPs by checking NIC configuration
    NIC_NAME=$(az vm show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$EXISTING_VM_NAME" \
      --query "networkProfile.networkInterfaces[0].id" \
      --output tsv 2>/dev/null | awk -F'/' '{print $NF}')
    
    if [[ -n "$NIC_NAME" ]]; then
      PUBLIC_IP_ID=$(az network nic show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NIC_NAME" \
        --query "ipConfigurations[0].publicIpAddress.id" \
        --output tsv 2>/dev/null || echo "")
      
      if [[ -n "$PUBLIC_IP_ID" && "$PUBLIC_IP_ID" != "null" ]]; then
        IS_PUBLIC="true"
      fi

      # Capture network details from the NIC/subnet to reuse existing VNet/Subnet/NSG
      SUBNET_ID=$(az network nic show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NIC_NAME" \
        --query "ipConfigurations[0].subnet.id" \
        --output tsv 2>/dev/null || echo "")

      if [[ -n "$SUBNET_ID" ]]; then
        KAFKA_SUBNET_NAME=$(basename "$SUBNET_ID")
        KAFKA_VNET_NAME=$(echo "$SUBNET_ID" | awk -F'/subnets/' '{print $1}' | awk -F'/virtualNetworks/' '{print $2}')
        KAFKA_VNET_RG=$(echo "$SUBNET_ID" | awk -F'/resourceGroups/' '{print $2}' | awk -F'/providers' '{print $1}')
        USE_EXISTING_NETWORK="true"
      fi

      # Capture existing NIC NSG to avoid re-association churn
      KAFKA_NSG_ID=$(az network nic show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NIC_NAME" \
        --query "networkSecurityGroup.id" \
        --output tsv 2>/dev/null || echo "")
    fi

    # Fallback detection: any public IPs in the RG that match the broker prefix
    if [[ "$IS_PUBLIC" != "true" ]]; then
      EXISTING_PIP_COUNT=$(az network public-ip list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?starts_with(name, '${KAFKA_NAME_PREFIX}-pip-')]|length(@)" \
        --output tsv 2>/dev/null || echo "0")
      if [[ ${EXISTING_PIP_COUNT:-0} -gt 0 ]]; then
        IS_PUBLIC="true"
      fi
    fi

    # Second fallback: NIC tags that explicitly mark PublicIP
    if [[ "$IS_PUBLIC" != "true" ]]; then
      NIC_PUBLIC_TAG_COUNT=$(az network nic list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?tags.PublicIP=='public']|length(@)" \
        --output tsv 2>/dev/null || echo "0")
      if [[ ${NIC_PUBLIC_TAG_COUNT:-0} -gt 0 ]]; then
        IS_PUBLIC="true"
      fi
    fi
    
    # Detect disk storage type from existing data disk
    DATA_DISK_NAME=$(az vm show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$EXISTING_VM_NAME" \
      --query "storageProfile.dataDisks[0].name" \
      --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$DATA_DISK_NAME" ]]; then
      KAFKA_DISK_TYPE=$(az disk show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DATA_DISK_NAME" \
        --query "sku.name" \
        --output tsv 2>/dev/null || echo "")
      
      if [[ "$KAFKA_DISK_TYPE" == "PremiumV2_LRS" ]]; then
        USE_PREMIUM_V2="true"
      fi
    fi
    
    log_success "Detected configuration:"
    log_info "  VM Size: ${KAFKA_VM_SIZE}"
    log_info "  Location: ${KAFKA_LOCATION}"
    log_info "  Zone: ${KAFKA_ZONE:-none}"
    log_info "  Name Prefix: ${KAFKA_NAME_PREFIX}"
    log_info "  Disk Type: ${KAFKA_DISK_TYPE:-Premium_LRS}"
    log_info "  Public IPs: ${IS_PUBLIC}"
    if [[ "$USE_EXISTING_NETWORK" == "true" ]]; then
      log_info "  Reusing VNet/Subnet: ${KAFKA_VNET_NAME}/${KAFKA_SUBNET_NAME} in RG ${KAFKA_VNET_RG:-$RESOURCE_GROUP}"
      if [[ -n "$KAFKA_NSG_ID" ]]; then
        log_info "  Existing NSG: ${KAFKA_NSG_ID}"
      fi
    fi
  else
    log_warn "Could not find existing broker VMs in resource group, using Terraform defaults"
  fi
else
  log_info "No existing brokers found in inventory, using Terraform default configuration"
fi

# If the resource group already exists, force Terraform to reuse network resources
if [[ "$RG_EXISTS" == "true" ]]; then
  USE_EXISTING_NETWORK="true"
  # Fill missing VNet/Subnet from the RG if not set above
  if [[ -z "$KAFKA_VNET_NAME" ]]; then
    KAFKA_VNET_NAME=$(az network vnet list \
      --resource-group "$RESOURCE_GROUP" \
      --query "[0].name" \
      --output tsv 2>/dev/null || echo "")
  fi
  if [[ -z "$KAFKA_SUBNET_NAME" && -n "$KAFKA_VNET_NAME" ]]; then
    KAFKA_SUBNET_NAME=$(az network vnet subnet list \
      --resource-group "$RESOURCE_GROUP" \
      --vnet-name "$KAFKA_VNET_NAME" \
      --query "[0].name" \
      --output tsv 2>/dev/null || echo "")
  fi
  if [[ -z "$KAFKA_VNET_RG" ]]; then
    KAFKA_VNET_RG="$RESOURCE_GROUP"
  fi
fi
echo ""

# Step 1: Provision new broker VMs via Terraform
log_info "Step 1: Provisioning $NUM_BROKERS new broker VM(s) via Terraform..."
cd "$TERRAFORM_DIR"

# Build Terraform command with all necessary variables to preserve existing resources
TERRAFORM_CMD="terraform apply -auto-approve"
CONTROL_NODE_USER="${USER}"
ANSIBLE_VENV_PATH_FOR_TF="${ANSIBLE_VENV_PATH:-/home/${CONTROL_NODE_USER}/ansible-venv}"
TERRAFORM_CMD="$TERRAFORM_CMD -var repository_base_dir=$PROJECT_ROOT"
TERRAFORM_CMD="$TERRAFORM_CMD -var repository_name=$REPO_NAME"
TERRAFORM_CMD="$TERRAFORM_CMD -var control_node_user=$CONTROL_NODE_USER"
TERRAFORM_CMD="$TERRAFORM_CMD -var ansible_venv_path=$ANSIBLE_VENV_PATH_FOR_TF"
TERRAFORM_CMD="$TERRAFORM_CMD -var ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
TERRAFORM_CMD="$TERRAFORM_CMD -var kafka_instance_count=$BROKER_COUNT"
TERRAFORM_CMD="$TERRAFORM_CMD -var resource_group_name=$RESOURCE_GROUP"

# Add detected configuration to preserve existing resources
if [[ -n "$KAFKA_VM_SIZE" ]]; then
  TERRAFORM_CMD="$TERRAFORM_CMD -var kafka_vm_size=$KAFKA_VM_SIZE"
fi

if [[ -n "$KAFKA_LOCATION" ]]; then
  TERRAFORM_CMD="$TERRAFORM_CMD -var resource_group_location=$KAFKA_LOCATION"
fi

if [[ -n "$KAFKA_ZONE" ]]; then
  TERRAFORM_CMD="$TERRAFORM_CMD -var kafka_vm_zone=$KAFKA_ZONE"
  TERRAFORM_CMD="$TERRAFORM_CMD -var enable_availability_zones=true"
else
  TERRAFORM_CMD="$TERRAFORM_CMD -var enable_availability_zones=false"
fi

if [[ "$USE_PREMIUM_V2" == "true" ]]; then
  TERRAFORM_CMD="$TERRAFORM_CMD -var use_premium_v2_disks=true"
else
  TERRAFORM_CMD="$TERRAFORM_CMD -var use_premium_v2_disks=false"
fi

if [[ "$IS_PUBLIC" == "true" ]]; then
  TERRAFORM_CMD="$TERRAFORM_CMD -var is_public=true"
else
  TERRAFORM_CMD="$TERRAFORM_CMD -var is_public=false"
fi

# Reuse existing network/VNet/Subnet/NSG when detected to avoid resource creation/diff
if [[ "$USE_EXISTING_NETWORK" == "true" ]]; then
  TERRAFORM_CMD="$TERRAFORM_CMD -var use_existing_kafka_network=true"
  if [[ -n "$KAFKA_VNET_NAME" ]]; then
    TERRAFORM_CMD="$TERRAFORM_CMD -var kafka_vnet_name=$KAFKA_VNET_NAME"
  fi
  if [[ -n "$KAFKA_SUBNET_NAME" ]]; then
    TERRAFORM_CMD="$TERRAFORM_CMD -var kafka_subnet_name=$KAFKA_SUBNET_NAME"
  fi
  if [[ -n "$KAFKA_VNET_RG" ]]; then
    TERRAFORM_CMD="$TERRAFORM_CMD -var existing_kafka_vnet_resource_group_name=$KAFKA_VNET_RG"
  fi
  if [[ -n "$KAFKA_NSG_ID" ]]; then
    TERRAFORM_CMD="$TERRAFORM_CMD -var kafka_nsg_id=$KAFKA_NSG_ID"
  fi
fi

log_info "Running: $TERRAFORM_CMD"
eval "$TERRAFORM_CMD" || {
  log_error "Terraform apply failed"
  exit 1
}
log_success "Broker VMs provisioned"
echo ""

# Ensure ansible-playbook is available (prefer control node venv)
ANSIBLE_VENV_PATH="${ANSIBLE_VENV_PATH:-/home/${USER}/ansible-venv}"
ANSIBLE_PLAYBOOK_BIN=$(command -v ansible-playbook || true)
if [[ -z "$ANSIBLE_PLAYBOOK_BIN" && -x "${ANSIBLE_VENV_PATH}/bin/ansible-playbook" ]]; then
  ANSIBLE_PLAYBOOK_BIN="${ANSIBLE_VENV_PATH}/bin/ansible-playbook"
  export PATH="${ANSIBLE_VENV_PATH}/bin:$PATH"
fi
if [[ -z "$ANSIBLE_PLAYBOOK_BIN" ]]; then
  log_error "ansible-playbook not found. Install Ansible or ensure ${ANSIBLE_VENV_PATH} exists."
  exit 1
fi

# Step 2-6: For each new broker, discover IP, update inventory, deploy Kafka, validate
BROKERS_DEPLOYED=()
HEALTH_CHECK_RESULTS=()
TEMP_HEALTH_DIR=$(mktemp -d)
trap "rm -rf $TEMP_HEALTH_DIR" EXIT

for ((i=CURRENT_BROKER_COUNT; i<BROKER_COUNT; i++)); do
  BROKER_INDEX=$i
  BROKER_SEQUENCE=$((i+1))
  # Consistent 0-indexed naming across all components:
  # - Terraform Index: 0, 1, 2...
  # - Azure VM Name: Uses existing name prefix (kafka_t1-broker-X or kafka-cluster-broker-X)
  # - Computer Name: kafka-broker-0, kafka-broker-1...
  # - Inventory Name: kafka-broker-0, kafka-broker-1...
  # - Kafka Node ID: 1, 2, 3... (1-indexed as required by KRaft)
  
  # Use detected name prefix or default
  if [[ -n "$KAFKA_NAME_PREFIX" ]]; then
    AZURE_VM_NAME="${KAFKA_NAME_PREFIX}-broker-${BROKER_INDEX}"
  else
    # Default for new deployments
    AZURE_VM_NAME="kafka-cluster-broker-${BROKER_INDEX}"
  fi
  
  if [[ -n "$BROKER_NAME" ]]; then
    CURRENT_BROKER_NAME="$BROKER_NAME"
  else
    CURRENT_BROKER_NAME="kafka-broker-${BROKER_INDEX}"
  fi
  
  log_info ""
  log_info "=========================================="
  log_info "Processing broker $((i-CURRENT_BROKER_COUNT+1))/$NUM_BROKERS"
  log_info "  Inventory Name: $CURRENT_BROKER_NAME"
  log_info "  Azure VM Name: $AZURE_VM_NAME"
  log_info "  Kafka Node ID: $BROKER_SEQUENCE"
  log_info "  Terraform Index: $BROKER_INDEX"
  log_info "=========================================="
  echo ""

  # Step 2: Discover broker IP from Azure
  log_info "Step 2: Discovering broker IP for Azure VM: $AZURE_VM_NAME..."
  # Prefer private IP (best practice for internal cluster communication)
  NEW_BROKER_IP=$(az vm list-ip-addresses \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?virtualMachine.name=='${AZURE_VM_NAME}'].virtualMachine.network.privateIpAddresses[0]" \
    --output tsv 2>/dev/null || echo "")

  # If private IP not found, fall back to public IP
  if [[ -z "$NEW_BROKER_IP" ]]; then
    NEW_BROKER_IP=$(az vm list-ip-addresses \
      --resource-group "$RESOURCE_GROUP" \
      --query "[?virtualMachine.name=='${AZURE_VM_NAME}'].virtualMachine.network.publicIpAddresses[0].ipAddress" \
      --output tsv 2>/dev/null || echo "")
  fi

  if [[ -z "$NEW_BROKER_IP" ]]; then
    log_error "Failed to discover IP for Azure VM '$AZURE_VM_NAME' in resource group '$RESOURCE_GROUP'"
    log_error "Make sure the VM was provisioned by Terraform and exists in Azure."
    exit 1
  fi

  log_success "Broker IP: $NEW_BROKER_IP"
  echo ""

  # Step 3: Update Ansible inventory
  log_info "Step 3: Updating Ansible inventory for $CURRENT_BROKER_NAME..."
  if grep -q "^$CURRENT_BROKER_NAME" "$INVENTORY_FILE"; then
    log_warn "$CURRENT_BROKER_NAME already in inventory, skipping"
  else
    # Add broker with Kafka node ID (1-indexed)
    echo "$CURRENT_BROKER_NAME ansible_host=$NEW_BROKER_IP private_ip=$NEW_BROKER_IP kafka_node_id=$BROKER_SEQUENCE" >> "$INVENTORY_FILE"
    log_success "Added $CURRENT_BROKER_NAME (Node ID: $BROKER_SEQUENCE) to inventory"
  fi
  echo ""

  # Step 4: Run Ansible scale-out playbook for this broker
  log_info "Step 4: Deploying Kafka on $CURRENT_BROKER_NAME via Ansible..."
  cd "$ANSIBLE_DIR"

  ANSIBLE_CMD="$ANSIBLE_PLAYBOOK_BIN -i $INVENTORY_FILE -u $ANSIBLE_USER playbooks/scale_out_kafka_broker.yml -e new_broker_host=$CURRENT_BROKER_NAME"
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    ANSIBLE_CMD="$ANSIBLE_CMD -e force_overwrite=true"
  fi

  log_info "Running: $ANSIBLE_CMD"
  eval "$ANSIBLE_CMD" || {
    log_error "Ansible playbook failed for $CURRENT_BROKER_NAME"
    log_error "This could be due to SSH connectivity issues or Kafka configuration errors."
    log_error "Check: 1) VNet peering, 2) NSG rules, 3) SSH key authorization"
    exit 1
  }
  log_success "Kafka deployed on $CURRENT_BROKER_NAME"
  BROKERS_DEPLOYED+=("$CURRENT_BROKER_NAME (Azure: $AZURE_VM_NAME, Node ID: $BROKER_SEQUENCE, IP: $NEW_BROKER_IP)")
  echo ""

  # Step 5: Validate this broker
  log_info "Step 5: Validating $CURRENT_BROKER_NAME integration..."
  sleep 10  # Wait for broker to settle

  # Check if broker is reachable
  if nc -zv "$NEW_BROKER_IP" 9092 &>/dev/null; then
    log_success "Broker port 9092 is accessible on $NEW_BROKER_IP"
  else
    log_warn "Could not verify port 9092 on $NEW_BROKER_IP; firewall rules may need adjustment"
  fi

  # Test SSH connectivity after Ansible deployment
  log_info "Testing SSH connectivity for health checks..."
  if [[ -n "$SSH_KEY" ]]; then
    if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$ANSIBLE_USER@$NEW_BROKER_IP" 'echo OK' &>/dev/null; then
      log_success "SSH authentication working for $ANSIBLE_USER@$NEW_BROKER_IP"
    else
      log_warn "SSH authentication failed; some health checks may be limited"
    fi
  else
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$ANSIBLE_USER@$NEW_BROKER_IP" 'echo OK' &>/dev/null; then
      log_success "SSH authentication working for $ANSIBLE_USER@$NEW_BROKER_IP"
    else
      log_warn "SSH not configured; some health checks will be limited"
    fi
  fi

  # Run health check on this broker
  log_info "Running health check for $CURRENT_BROKER_NAME..."
  HEALTH_CHECK_FILE="$TEMP_HEALTH_DIR/${CURRENT_BROKER_NAME}_health_check.log"
  
  SSH_USER="$ANSIBLE_USER" \
  SSH_KEY="$SSH_KEY" \
  BROKER_HOST="$NEW_BROKER_IP" \
  BOOTSTRAP_SERVER="$NEW_BROKER_IP:9092" \
  "$SCRIPT_DIR/kafka_health_check.sh" > "$HEALTH_CHECK_FILE" 2>&1 || {
    log_warn "Health check had issues for $CURRENT_BROKER_NAME; see output above"
  }
  
  # Capture health check summary
  HEALTH_SUMMARY=$(grep -E "PASS|FAIL|WARN" "$HEALTH_CHECK_FILE" | grep "\[" | head -8)
  HEALTH_CHECK_RESULTS+=("$CURRENT_BROKER_NAME ($NEW_BROKER_IP)")
  HEALTH_CHECK_RESULTS+=("$HEALTH_SUMMARY")
  HEALTH_CHECK_RESULTS+=("")
  
  # Display output
  cat "$HEALTH_CHECK_FILE"
  echo ""
done

# Step 6: Summary
log_success "Scale-out complete!"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "SCALE-OUT SUMMARY"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Brokers deployed ($NUM_BROKERS total):"
for broker in "${BROKERS_DEPLOYED[@]}"; do
  echo "  ✓ $broker"
done
echo ""

# Display comprehensive health check summary
if [[ ${#HEALTH_CHECK_RESULTS[@]} -gt 0 ]]; then
  echo "════════════════════════════════════════════════════════════════"
  echo "HEALTH CHECK SUMMARY (All Deployed Brokers)"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  for item in "${HEALTH_CHECK_RESULTS[@]}"; do
    echo "$item"
  done
  echo ""
fi

echo "════════════════════════════════════════════════════════════════"
echo "CLUSTER STATUS"
echo "════════════════════════════════════════════════════════════════"
echo "Total brokers now: $BROKER_COUNT"
echo "Newly deployed brokers: $NUM_BROKERS"
echo ""
echo "Cluster information:"
echo "  Mode: ZooKeeper"
echo "  ZooKeeper connect: <broker-ip>:2181 (ensemble)"
echo ""
echo "Next steps:"
echo "  1. Verify ZooKeeper broker registration: /opt/kafka/bin/zookeeper-shell.sh <broker-ip>:2181 ls /brokers/ids"
echo "  2. Verify in Prometheus: curl -s http://localhost:9090/api/v1/targets | grep kafka"
echo "  3. Check topic replication: ansible -i $INVENTORY_FILE kafka -u $ANSIBLE_USER -m shell -a '/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe'"
echo "  4. Monitor in Grafana: http://<management-node>:3000"
echo "════════════════════════════════════════════════════════════════"
