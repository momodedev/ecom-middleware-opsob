# Control Node Deployment for Kafka Cluster (OB)

This Terraform module deploys a control node and related resources in Azure for managing Kafka clusters. The control node serves as a management jumpbox with all necessary tools pre-installed (Terraform, Ansible, Azure CLI).

## Architecture

```
Internet → Control Node (Public IP) → VNet Peering → Kafka Brokers (Private IPs)
                                                    ↓
                                            NAT Gateway → Internet
```

## Resources Deployed

### Network Resources
- **Resource Group**: Contains all control node resources
- **Virtual Network (VNet)**: Isolated network for control node (172.17.0.0/16)
- **Subnet**: Control node subnet (172.17.1.0/24)
- **Network Security Group (NSG)**: Security rules for SSH, Prometheus, and Grafana access
- **Public IP**: Static public IP for SSH access to control node

### Compute Resources
- **Control Node VM**: Rocky Linux 9 VM with managed identity
- **System Assigned Identity**: With Contributor role on subscription
- **Network Interface**: Connected to control subnet with public IP

### Software Pre-installed on Control Node
- Terraform v1.x+
- Azure CLI
- Ansible with Azure collections
- Python 3 with virtualenv
- jq, curl, wget, and other utilities

## Quick Start

### Prerequisites

1. **Azure Subscription**: Active Azure subscription with appropriate permissions
2. **SSH Key Pair**: ED25519 or RSA key pair for SSH access
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
   ```
3. **Azure CLI**: Installed locally for initial authentication
   ```bash
   az login
   ```

### Deployment Steps

1. **Navigate to the directory**:
   ```bash
   cd terraform/kafka/manage_node_ob
   ```

2. **Configure variables**:
   Edit `secret.tfvars` with your specific values:
   - Set your `ARM_SUBSCRIPTION_ID`
   - Customize resource group names and locations
   - Choose VM sizes appropriate for your workload
   - Configure network settings (use existing or create new)

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Plan deployment** (optional):
   ```bash
   terraform plan -var-file='secret.tfvars'
   ```

5. **Apply configuration**:
   ```bash
   terraform apply -var-file='secret.tfvars'
   ```

6. **Access the control node**:
   After deployment completes, get the public IP:
   ```bash
   CONTROL_IP=$(terraform output -raw control_public_ip)
   ssh -p 6666 azureadmin@$CONTROL_IP
   ```

## Configuration Options

### Using Existing Network Resources

To reuse existing VNet, subnet, and NSG:

```hcl
use_existing_control_network = true
control_vnet_name            = "existing-vnet-name"
control_subnet_name          = "existing-subnet-name"
control_nsg_id               = "/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/networkSecurityGroups/..."
```

### Deployment Modes

- **`together`**: Deploys control node and automatically initiates Kafka cluster deployment
- **`separate`**: Deploys control node only (manual Kafka deployment via SSH)

### Network Security

The NSG includes the following inbound rules:
- **SSH** (port 6666 by default): Remote access
- **Prometheus** (port 9090): Metrics scraping
- **Grafana** (port 3000): Dashboard access

## Outputs

After deployment, retrieve useful information:

```bash
# Get control node public IP
terraform output control_public_ip

# Get control node private IP
terraform output control_private_ip

# Get resource group name
terraform output resource_group_name
```

## Post-Deployment

Once logged into the control node:

1. **Verify Azure CLI access**:
   ```bash
   az login --identity
   az account show
   ```

2. **Access Ansible**:
   ```bash
   source ~/ansible-venv/bin/activate
   ansible --version
   ```

3. **Deploy Kafka cluster** (if deploy_mode = "separate"):
   ```bash
   cd ~/ecom-middleware-ops/ansible
   ansible-playbook -i inventory/kafka_hosts playbooks/deploy_kafka_playbook.yaml
   ```

4. **Access monitoring dashboards**:
   - Grafana: `http://<control-ip>:3000`
   - Prometheus: `http://<control-ip>:9090`

## Cleanup

To destroy all resources:

```bash
terraform destroy -var-file='secret.tfvars'
```

**Warning**: This will delete all resources including any Kafka clusters and data.

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**:
   - Verify the control node is running: `az vm show -d -g <rg-name> -n control-node`
   - Check NSG rules allow SSH on configured port
   - Ensure you're using the correct SSH port (default: 6666)

2. **Cloud-init Failure**:
   - SSH to the VM and check logs: `sudo cat /var/log/cloud-init-output.log`
   - Verify managed identity has Contributor role

3. **Terraform State Issues**:
   - If state file is corrupted, import existing resources:
     ```bash
     terraform import azurerm_resource_group.example <rg-name>
     ```

## Security Best Practices

- Use ED25519 SSH keys instead of RSA
- Restrict NSG SSH access to known IP ranges in production
- Enable Azure Defender for enhanced security monitoring
- Use Azure Private Link for additional isolation if needed
- Regularly update the control node OS and packages

## Support

For issues or questions:
1. Check cloud-init logs on control node: `/var/log/cloud-init-output.log`
2. Review Terraform state: `terraform state list`
3. Validate Azure resources: `az resource list -g <resource-group-name>`
