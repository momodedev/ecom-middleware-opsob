#!/bin/bash
###############################################################################
# Script: verify_no_public_ips.sh
# Purpose: Verify Kafka broker VMs have NO public IPs attached
# Usage: bash verify_no_public_ips.sh <resource-group>
###############################################################################

set -e

# Default resource group
RESOURCE_GROUP="${1:-kafka_t1}"

echo "=================================================="
echo "Kafka Broker Public IP Verification"
echo "=================================================="
echo "Resource Group: $RESOURCE_GROUP"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "❌ ERROR: Azure CLI not found. Please install it first."
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    echo "❌ ERROR: Not logged in to Azure. Run 'az login' first."
    exit 1
fi

echo "Step 1: Checking broker VMs..."
echo "---"

# Get all broker VMs
BROKER_VMS=$(az vm list -g "$RESOURCE_GROUP" --query "[?contains(name, 'broker')].name" -o tsv)

if [ -z "$BROKER_VMS" ]; then
    echo "⚠️  WARNING: No broker VMs found in resource group '$RESOURCE_GROUP'"
    exit 0
fi

TOTAL_BROKERS=$(echo "$BROKER_VMS" | wc -l | tr -d ' ')
echo "Found $TOTAL_BROKERS broker VMs"
echo ""

# Check each broker VM for public IPs
HAS_PUBLIC_IP=false
BROKER_COUNT=0

echo "Step 2: Checking public IP configuration..."
echo "---"

for VM_NAME in $BROKER_VMS; do
    BROKER_COUNT=$((BROKER_COUNT + 1))
    echo "Checking: $VM_NAME"
    
    # Get NIC IDs for this VM
    NIC_IDS=$(az vm show -g "$RESOURCE_GROUP" -n "$VM_NAME" --query "networkProfile.networkInterfaces[].id" -o tsv)
    
    # Check each NIC for public IP
    for NIC_ID in $NIC_IDS; do
        NIC_NAME=$(basename "$NIC_ID")
        
        # Get public IP configuration
        PUBLIC_IP_ID=$(az network nic show --ids "$NIC_ID" --query "ipConfigurations[0].publicIpAddress.id" -o tsv)
        
        if [ -n "$PUBLIC_IP_ID" ] && [ "$PUBLIC_IP_ID" != "null" ]; then
            PUBLIC_IP=$(az network public-ip show --ids "$PUBLIC_IP_ID" --query "ipAddress" -o tsv 2>/dev/null || echo "Unknown")
            echo "  ❌ FAILED: Has public IP $PUBLIC_IP (NIC: $NIC_NAME)"
            HAS_PUBLIC_IP=true
        else
            echo "  ✅ PASSED: No public IP (NIC: $NIC_NAME)"
        fi
    done
    echo ""
done

echo "Step 3: Checking NAT Gateway configuration..."
echo "---"

# Check NAT Gateway (should have public IP)
NAT_GATEWAY=$(az network nat gateway list -g "$RESOURCE_GROUP" --query "[0].name" -o tsv)

if [ -n "$NAT_GATEWAY" ] && [ "$NAT_GATEWAY" != "null" ]; then
    NAT_PUBLIC_IP=$(az network nat gateway show -g "$RESOURCE_GROUP" -n "$NAT_GATEWAY" \
        --query "publicIpAddresses[0].id" -o tsv | xargs -I{} az network public-ip show --ids {} --query "ipAddress" -o tsv 2>/dev/null || echo "Not found")
    echo "NAT Gateway: $NAT_GATEWAY"
    echo "  ✅ Public IP: $NAT_PUBLIC_IP (for outbound traffic only)"
else
    echo "⚠️  WARNING: No NAT Gateway found"
fi
echo ""

echo "Step 4: Summary"
echo "=================================================="
echo "Total broker VMs checked: $BROKER_COUNT"

if [ "$HAS_PUBLIC_IP" = true ]; then
    echo "Status: ❌ FAILED - Some brokers have public IPs"
    echo ""
    echo "Action Required:"
    echo "  1. Run: cd terraform/kafka && terraform destroy"
    echo "  2. Verify network interface config has: public_ip_address_id = null"
    echo "  3. Run: terraform apply"
    echo ""
    echo "See: REMOVE_PUBLIC_IPS.md for detailed instructions"
    exit 1
else
    echo "Status: ✅ PASSED - No broker VMs have public IPs"
    echo ""
    echo "Configuration is correct! Brokers are private-only."
    echo "Outbound internet access is provided by NAT Gateway."
    exit 0
fi
