#!/bin/bash
# OceanBase Automated Deployment Script
# This script deploys the complete OceanBase cluster with a single command

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "  OceanBase Cluster Automated Deployment"
echo "=========================================="
echo ""
echo "Repository Root: $REPO_ROOT"
echo "Working Directory: $SCRIPT_DIR"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "Error: Terraform is not installed or not in PATH"
    exit 1
fi

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed or not in PATH"
    exit 1
fi

# Check if logged into Azure
if ! az account show &> /dev/null; then
    echo "Error: Not logged into Azure CLI"
    echo "Please run: az login"
    exit 1
fi

# Check if secret.tfvars exists
if [ ! -f "$SCRIPT_DIR/secret.tfvars" ]; then
    echo "Error: secret.tfvars not found in $SCRIPT_DIR"
    echo "Please copy secret.tfvars.example to secret.tfvars and configure it"
    exit 1
fi

echo "✓ All prerequisites met"
echo ""

# Navigate to terraform directory
cd "$SCRIPT_DIR"

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

echo ""
echo "=========================================="
echo "  Starting Full Deployment"
echo "=========================================="
echo ""
echo "This will:"
echo "1. Deploy Azure infrastructure (Resource Group, VNet, VMs, Disks)"
echo "2. Wait for VMs to be ready"
echo "3. Deploy OceanBase cluster using Ansible"
echo "4. Deploy monitoring stack (Grafana + Prometheus)"
echo ""
echo "Estimated time: 30-45 minutes"
echo ""

# Run terraform apply with auto-approve
read -p "Do you want to proceed with the deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo "Starting deployment at $(date)"
echo ""

# Apply Terraform configuration
terraform apply -var-file='secret.tfvars' -auto-approve

echo ""
echo "=========================================="
echo "  Deployment Completed Successfully!"
echo "=========================================="
echo ""
echo "Deployment completed at $(date)"
echo ""

# Display outputs
echo "Getting deployment information..."
echo ""

# Get control node IP (for monitoring access)
CONTROL_IP=""
if [ -f "$REPO_ROOT/terraform/manage_node_ob/terraform.tfstate" ]; then
    CONTROL_IP=$(cd "$REPO_ROOT/terraform/manage_node_ob" && terraform output -raw control_public_ip 2>/dev/null || echo "")
fi

echo "=========================================="
echo "  Connection Information"
echo "=========================================="
echo ""

# Show observer IPs
echo "OceanBase Observer Nodes:"
terraform output -json observer_private_ips | jq -r '.[]' | while read ip; do
    echo "  - $ip"
done
echo ""

# Show SSH command
echo "SSH to first observer:"
OBSERVER_IP=$(terraform output -json observer_private_ips | jq -r '.[0]')
SSH_KEY=$(terraform output -raw ssh_private_key_path 2>/dev/null || echo "~/.ssh/id_ed25519")
echo "  ssh -i $SSH_KEY oceanadmin@$OBSERVER_IP"
echo ""

# Show monitoring URLs
if [ -n "$CONTROL_IP" ]; then
    echo "Monitoring Dashboards:"
    echo "  Grafana:    http://$CONTROL_IP:3000 (admin/admin)"
    echo "  Prometheus: http://$CONTROL_IP:9090"
    echo ""
fi

# Show next steps
echo "=========================================="
echo "  Next Steps"
echo "=========================================="
echo ""
echo "1. SSH to observer node:"
echo "   ssh -i $SSH_KEY oceanadmin@$OBSERVER_IP"
echo ""
echo "2. Switch to admin user:"
echo "   su - admin"
echo ""
echo "3. Load OceanBase environment:"
echo "   source ~/.oceanbase-all-in-one/bin/env.sh"
echo ""
echo "4. Verify cluster status:"
echo "   obd cluster list"
echo "   obd cluster display ob_cluster"
echo ""
echo "5. Connect to database:"
echo "   obclient -h127.0.0.1 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -A"
echo ""
echo "6. Access Grafana dashboard:"
if [ -n "$CONTROL_IP" ]; then
    echo "   http://$CONTROL_IP:3000"
else
    echo "   http://<control-node-public-ip>:3000"
fi
echo ""

echo "=========================================="
echo "  Important Notes"
echo "=========================================="
echo ""
echo "⚠️  Please change the default root password!"
echo "⚠️  Save these outputs for future reference"
echo "⚠️  Keep secret.tfvars secure and never commit it to Git"
echo ""
