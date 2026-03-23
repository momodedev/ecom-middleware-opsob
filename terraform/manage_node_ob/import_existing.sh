#!/bin/bash
# Import existing Azure resources into Terraform state
# This script helps import resources that already exist in Azure

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load variables from secret.tfvars
if [ -f "secret.tfvars" ]; then
    echo_info "Loading variables from secret.tfvars..."
    source <(grep -v '^#' secret.tfvars | sed 's/ *= */=/g' | sed 's/"//g')
else
    echo_error "secret.tfvars not found!"
    exit 1
fi

# Get resource group name
RG_NAME="${resource_group_name:-control-ob-rg}"
SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID}"

echo_info "Subscription ID: $SUBSCRIPTION_ID"
echo_info "Resource Group: $RG_NAME"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo_info "Initializing Terraform..."
    terraform init
fi

# Function to get resource ID using Azure CLI
get_resource_id() {
    local resource_type=$1
    local resource_name=$2
    local rg_name=$3
    
    az resource show \
        --resource-group "$rg_name" \
        --name "$resource_name" \
        --resource-type "$resource_type" \
        --query "id" \
        --output tsv 2>/dev/null || echo ""
}

# Function to import a resource
import_resource() {
    local address=$1
    local resource_id=$2
    
    if [ -z "$resource_id" ]; then
        echo_warn "Resource $address not found in Azure, skipping import..."
        return 0
    fi
    
    # Check if already in state
    if terraform state list 2>/dev/null | grep -q "$address"; then
        echo_warn "Resource $address already in state, skipping..."
        return 0
    fi
    
    echo_info "Importing $address..."
    echo_info "  Resource ID: $resource_id"
    
    if terraform import "$address" "$resource_id"; then
        echo_info "✓ Successfully imported $address"
    else
        echo_error "✗ Failed to import $address"
        return 1
    fi
}

echo_info "=========================================="
echo_info "Checking for existing resources to import"
echo_info "=========================================="
echo_info ""

# Step 1: Check and import Resource Group
echo_info "Step 1: Checking Resource Group..."
RG_ID=$(az group show --name "$RG_NAME" --query "id" --output tsv 2>/dev/null || echo "")
if [ -n "$RG_ID" ]; then
    echo_info "Found existing Resource Group: $RG_NAME"
    import_resource "data.azurerm_resource_group.existing" "$RG_ID" || true
else
    echo_warn "Resource Group $RG_NAME not found, will be created"
fi
echo_info ""

# Step 2: Check and import VNet
echo_info "Step 2: Checking Virtual Network..."
VNET_NAME="${control_vnet_name:-control-ob-vnet}"
VNET_ID=$(get_resource_id "Microsoft.Network/virtualNetworks" "$VNET_NAME" "$RG_NAME")
if [ -n "$VNET_ID" ]; then
    echo_info "Found existing VNet: $VNET_NAME"
    import_resource "data.azurerm_virtual_network.existing" "$VNET_ID" || true
else
    echo_warn "VNet $VNET_NAME not found, will be created"
fi
echo_info ""

# Step 3: Check and import Subnet
echo_info "Step 3: Checking Subnet..."
SUBNET_NAME="${control_subnet_name:-control-ob-subnet}"
SUBNET_ID=$(az network vnet subnet show \
    --resource-group "$RG_NAME" \
    --vnet-name "$VNET_NAME" \
    --name "$SUBNET_NAME" \
    --query "id" \
    --output tsv 2>/dev/null || echo "")
if [ -n "$SUBNET_ID" ]; then
    echo_info "Found existing Subnet: $SUBNET_NAME"
    import_resource "data.azurerm_subnet.existing" "$SUBNET_ID" || true
else
    echo_warn "Subnet $SUBNET_NAME not found, will be created"
fi
echo_info ""

# Step 4: Check and import NSG
echo_info "Step 4: Checking Network Security Group..."
NSG_NAME="${control_nsg_name:-control-ob-nsg}"
if [ -n "$control_nsg_id" ] && [ "$control_nsg_id" != '""' ]; then
    echo_info "Using existing NSG from control_nsg_id: $control_nsg_id"
    import_resource "data.azurerm_network_security_group.existing" "$control_nsg_id" || true
else
    NSG_ID=$(get_resource_id "Microsoft.Network/networkSecurityGroups" "$NSG_NAME" "$RG_NAME")
    if [ -n "$NSG_ID" ]; then
        echo_info "Found existing NSG: $NSG_NAME"
        import_resource "data.azurerm_network_security_group.existing" "$NSG_ID" || true
    else
        echo_warn "NSG $NSG_NAME not found, will be created"
    fi
fi
echo_info ""

# Step 5: Check and import Public IP
echo_info "Step 5: Checking Public IP..."
PIP_NAME="control-ip"
PIP_ID=$(get_resource_id "Microsoft.Network/publicIPAddresses" "$PIP_NAME" "$RG_NAME")
if [ -n "$PIP_ID" ]; then
    echo_info "Found existing Public IP: $PIP_NAME"
    import_resource "data.azurerm_public_ip.existing" "$PIP_ID" || true
else
    echo_warn "Public IP $PIP_NAME not found, will be created"
fi
echo_info ""

# Step 6: Check and import NIC
echo_info "Step 6: Checking Network Interface..."
NIC_NAME="control-nic"
NIC_ID=$(get_resource_id "Microsoft.Network/networkInterfaces" "$NIC_NAME" "$RG_NAME")
if [ -n "$NIC_ID" ]; then
    echo_info "Found existing NIC: $NIC_NAME"
    import_resource "data.azurerm_network_interface.existing" "$NIC_ID" || true
else
    echo_warn "NIC $NIC_NAME not found, will be created"
fi
echo_info ""

# Step 7: Check and import VM (using azapi since azurerm doesn't have VM data source)
echo_info "Step 7: Checking Virtual Machine..."
VM_NAME="control-node"
VM_ID=$(get_resource_id "Microsoft.Compute/virtualMachines" "$VM_NAME" "$RG_NAME")
if [ -n "$VM_ID" ]; then
    echo_info "Found existing VM: $VM_NAME"
    import_resource "data.azapi_resource.vm_existing" "$VM_ID" || true
else
    echo_warn "VM $VM_NAME not found, will be created"
fi
echo_info ""

# Step 8: Check and import Role Assignment (if VM exists)
if [ -n "$VM_ID" ]; then
    echo_info "Step 8: Checking Role Assignment..."
    PRINCIPAL_ID=$(az vm show --ids "$VM_ID" --query "identity.principalId" --output tsv 2>/dev/null || echo "")
    if [ -n "$PRINCIPAL_ID" ]; then
        echo_info "Found VM managed identity principal ID: $PRINCIPAL_ID"
        # Try to find existing role assignment
        ROLE_ASSIGNMENT=$(az role assignment list \
            --scope "/subscriptions/$SUBSCRIPTION_ID" \
            --role "Contributor" \
            --assignee "$PRINCIPAL_ID" \
            --query "[0].id" \
            --output tsv 2>/dev/null || echo "")
        if [ -n "$ROLE_ASSIGNMENT" ]; then
            echo_info "Found existing Role Assignment"
            import_resource "data.azurerm_role_assignment.existing[0]" "$ROLE_ASSIGNMENT" || true
        else
            echo_warn "Role Assignment not found, will be created"
        fi
    fi
fi
echo_info ""

echo_info "=========================================="
echo_info "Import process completed!"
echo_info "=========================================="
echo_info ""
echo_info "Next steps:"
echo_info "1. Run 'terraform plan -var-file='secret.tfvars'' to see what needs to be created"
echo_info "2. Resources marked as 'will be created' will be provisioned"
echo_info "3. Imported resources will be managed by Terraform going forward"
echo_info ""
echo_info "To view imported resources:"
echo_info "  terraform state list"
echo_info ""
