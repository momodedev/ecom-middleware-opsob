#!/bin/bash
# Deployment helper script for manage_node_ob Terraform configuration
# This script automates common deployment tasks including resource import

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    echo_info "Checking prerequisites..."
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        echo_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        echo_warn "Azure CLI is not installed. You won't be able to authenticate."
    fi
    
    # Check if secret.tfvars exists
    if [ ! -f "secret.tfvars" ]; then
        echo_error "secret.tfvars not found. Please create it from the template."
        exit 1
    fi
    
    echo_info "Prerequisites check passed!"
}

# Function to initialize Terraform
init_terraform() {
    echo_info "Initializing Terraform..."
    terraform init
    echo_info "Terraform initialized successfully!"
}

# Function to validate configuration
validate_config() {
    echo_info "Validating Terraform configuration..."
    terraform validate
    echo_info "Configuration is valid!"
}

# Function to plan deployment
plan_deployment() {
    echo_info "Planning deployment..."
    terraform plan -var-file='secret.tfvars' -out=tfplan
    echo_info "Deployment plan created and saved to tfplan"
}

# Function to apply deployment
apply_deployment() {
    echo_info "Applying Terraform configuration..."
    terraform apply -var-file='secret.tfvars' -auto-approve
    
    echo_info ""
    echo_info "=========================================="
    echo_info "Deployment completed successfully!"
    echo_info "=========================================="
    echo_info ""
    
    # Get control node public IP
    CONTROL_IP=$(terraform output -raw control_public_ip 2>/dev/null || echo "Not available yet")
    echo_info "Control Node Public IP: $CONTROL_IP"
    echo_info ""
    echo_info "To connect to the control node:"
    echo_info "  ssh -p 6666 azureadmin@$CONTROL_IP"
    echo_info ""
    echo_info "To access Grafana dashboard:"
    echo_info "  http://$CONTROL_IP:3000"
    echo_info ""
    echo_info "To access Prometheus:"
    echo_info "  http://$CONTROL_IP:9090"
    echo_info ""
}

# Function to show outputs
show_outputs() {
    echo_info "Terraform Outputs:"
    echo_info "==================="
    terraform output
}

# Function to destroy deployment
destroy_deployment() {
    echo_warn "WARNING: This will destroy all resources!"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo_info "Aborted by user."
        exit 0
    fi
    
    echo_info "Destroying deployment..."
    terraform destroy -var-file='secret.tfvars' -auto-approve
    echo_info "Deployment destroyed!"
}

# Function to authenticate with Azure
azure_login() {
    echo_info "Authenticating with Azure CLI..."
    
    if command -v az &> /dev/null; then
        az login --use-device-code
        echo_info "Azure authentication successful!"
    else
        echo_error "Azure CLI is not installed."
        exit 1
    fi
}

# Function to import existing resources
import_existing() {
    echo_info "Importing existing Azure resources into Terraform state..."
    
    if [ -f "import_existing.sh" ]; then
        bash import_existing.sh
    else
        echo_error "import_existing.sh not found!"
        exit 1
    fi
}

# Function to check existing resources
check_existing() {
    echo_info "Checking for existing resources in Azure..."
    
    if [ ! -f "secret.tfvars" ]; then
        echo_error "secret.tfvars not found!"
        exit 1
    fi
    
    # Load variables
    source <(grep -v '^#' secret.tfvars | sed 's/ *= */=/g' | sed 's/"//g')
    
    RG_NAME="${resource_group_name:-control-ob-rg}"
    
    echo_info "Resource Group: $RG_NAME"
    echo_info ""
    
    # Check each resource type
    echo_info "Checking Resource Group..."
    if az group show --name "$RG_NAME" &>/dev/null; then
        echo_info "  ✓ Resource Group exists"
    else
        echo_info "  ✗ Resource Group does not exist (will be created)"
    fi
    
    VNET_NAME="${control_vnet_name:-control-ob-vnet}"
    echo_info "Checking Virtual Network ($VNET_NAME)..."
    if az network vnet show --resource-group "$RG_NAME" --name "$VNET_NAME" &>/dev/null; then
        echo_info "  ✓ VNet exists"
    else
        echo_info "  ✗ VNet does not exist (will be created)"
    fi
    
    SUBNET_NAME="${control_subnet_name:-control-ob-subnet}"
    echo_info "Checking Subnet ($SUBNET_NAME)..."
    if az network vnet subnet show --resource-group "$RG_NAME" --vnet-name "$VNET_NAME" --name "$SUBNET_NAME" &>/dev/null; then
        echo_info "  ✓ Subnet exists"
    else
        echo_info "  ✗ Subnet does not exist (will be created)"
    fi
    
    NSG_NAME="${control_nsg_name:-control-ob-nsg}"
    echo_info "Checking NSG ($NSG_NAME)..."
    if az network nsg show --resource-group "$RG_NAME" --name "$NSG_NAME" &>/dev/null; then
        echo_info "  ✓ NSG exists"
    else
        echo_info "  ✗ NSG does not exist (will be created)"
    fi
    
    echo_info "Checking Public IP (control-ip)..."
    if az network public-ip show --resource-group "$RG_NAME" --name "control-ip" &>/dev/null; then
        echo_info "  ✓ Public IP exists"
    else
        echo_info "  ✗ Public IP does not exist (will be created)"
    fi
    
    echo_info "Checking NIC (control-nic)..."
    if az network nic show --resource-group "$RG_NAME" --name "control-nic" &>/dev/null; then
        echo_info "  ✓ NIC exists"
    else
        echo_info "  ✗ NIC does not exist (will be created)"
    fi
    
    echo_info "Checking VM (control-node)..."
    if az vm show --resource-group "$RG_NAME" --name "control-node" &>/dev/null; then
        echo_info "  ✓ VM exists"
    else
        echo_info "  ✗ VM does not exist (will be created)"
    fi
    
    echo_info ""
    echo_info "Summary:"
    echo_info "  - Resources marked with ✓ will be imported into state"
    echo_info "  - Resources marked with ✗ will be created"
    echo_info ""
    echo_info "To import existing resources, run: $0 import"
}

# Main script logic
case "${1:-}" in
    init)
        check_prerequisites
        init_terraform
        ;;
    validate)
        validate_config
        ;;
    plan)
        check_prerequisites
        init_terraform
        plan_deployment
        ;;
    apply)
        check_prerequisites
        init_terraform
        apply_deployment
        ;;
    deploy)
        check_prerequisites
        init_terraform
        plan_deployment
        apply_deployment
        ;;
    destroy)
        check_prerequisites
        destroy_deployment
        ;;
    output)
        show_outputs
        ;;
    auth)
        azure_login
        ;;
    import)
        check_prerequisites
        init_terraform
        import_existing
        ;;
    check)
        check_existing
        ;;
    *)
        echo "Usage: $0 {init|validate|plan|apply|deploy|destroy|output|auth|import|check}"
        echo ""
        echo "Commands:"
        echo "  init     - Initialize Terraform"
        echo "  validate - Validate Terraform configuration"
        echo "  plan     - Create deployment plan"
        echo "  apply    - Apply Terraform configuration"
        echo "  deploy   - Plan and apply (full deployment)"
        echo "  destroy  - Destroy all resources"
        echo "  output   - Show Terraform outputs"
        echo "  auth     - Authenticate with Azure CLI"
        echo "  import   - Import existing Azure resources into Terraform state"
        echo "  check    - Check which resources exist in Azure"
        echo ""
        echo "Examples:"
        echo "  $0 deploy    # Full deployment"
        echo "  $0 import    # Import existing resources"
        echo "  $0 check     # Check what exists in Azure"
        echo "  $0 destroy   # Destroy all resources"
        exit 1
        ;;
esac
