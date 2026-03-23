# Quick Start Guide - Control Node Deployment

## Prerequisites Checklist

- [ ] Azure subscription with Contributor or Owner access
- [ ] Azure CLI installed (`az --version`)
- [ ] Terraform installed (`terraform --version`)
- [ ] SSH key pair generated (ED25519 recommended)
- [ ] Git client (optional, for version control)

## Step-by-Step Deployment

### Step 1: Authenticate with Azure

```bash
# Login to Azure
az login --use-device-code

# Verify subscription
az account show

# Set correct subscription if needed
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### Step 2: Configure Variables

Edit `secret.tfvars` with your values:

```bash
# Open the file in your editor
code secret.tfvars  # VS Code
# or
vim secret.tfvars   # Vim
# or
nano secret.tfvars  # Nano
```

**Required Changes:**
1. `ARM_SUBSCRIPTION_ID` - Your Azure subscription ID
2. `resource_group_name` - Desired resource group name
3. `resource_group_location` - Azure region (e.g., "westus", "eastus")
4. Review and adjust VM sizes if needed

**Optional Changes:**
- Use existing network resources (set `use_existing_control_network = true`)
- Change SSH port for security
- Customize Kafka cluster settings

### Step 3: Initialize Terraform

```bash
cd terraform/kafka/manage_node_ob
terraform init
```

Expected output: `Terraform has been successfully initialized!`

### Step 4: Validate Configuration

```bash
terraform validate
```

Expected output: `The configuration is valid.`

### Step 5: Preview Changes (Optional but Recommended)

```bash
terraform plan -var-file='secret.tfvars'
```

Review the planned changes carefully. You should see:
- Resource group creation (or reference to existing)
- VNet and subnet creation
- NSG with security rules
- Public IP allocation
- Network interface
- Virtual machine
- Role assignment

### Step 6: Deploy Resources

```bash
terraform apply -var-file='secret.tfvars'
```

When prompted, type `yes` to confirm.

**Deployment Time:** Approximately 5-10 minutes

### Step 7: Access the Control Node

After successful deployment:

```bash
# Get the public IP
CONTROL_IP=$(terraform output -raw control_public_ip)
echo "Control Node IP: $CONTROL_IP"

# Connect via SSH (replace with actual IP)
ssh -p 6666 azureadmin@$CONTROL_IP
```

### Step 8: Verify Installation

Once logged into the control node:

```bash
# Check Azure CLI
az login --identity
az vm list

# Check Terraform
terraform --version

# Check Ansible
source ~/ansible-venv/bin/activate
ansible --version
```

## Post-Deployment Tasks

### Access Monitoring Dashboards

1. **Grafana** (Default credentials: admin/admin)
   ```
   http://<CONTROL_IP>:3000
   ```

2. **Prometheus**
   ```
   http://<CONTROL_IP>:9090
   ```

### Deploy Kafka Cluster

If you used `deploy_mode = "together"`, Kafka deployment may have already started. To manually deploy:

```bash
# SSH to control node first
ssh -p 6666 azureadmin@$CONTROL_IP

# Navigate to Ansible directory
cd ~/ecom-middleware-ops/ansible

# Activate Ansible virtual environment
source ~/ansible-venv/bin/activate

# Run Kafka deployment playbook
ansible-playbook -i inventory/kafka_hosts playbooks/deploy_kafka_playbook.yaml
```

### Monitor Deployment Progress

```bash
# Check Kafka broker status
ansible-playbook playbooks/check_kafka_status.yml

# View health check results
./scripts/kafka_health_check.sh
```

## Troubleshooting

### Issue: Terraform init fails

**Solution:** Ensure you have internet connectivity and can reach HashiCorp releases:
```bash
curl https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
```

### Issue: Azure authentication fails

**Solution:** Re-authenticate with device code:
```bash
az login --use-device-code
# Follow the instructions in terminal
```

### Issue: SSH connection refused

**Solutions:**
1. Verify VM is running: `az vm show -d -g <RG_NAME> -n control-node --query powerState`
2. Check NSG rules in Azure Portal
3. Verify SSH port in `secret.tfvars`
4. Check cloud-init logs on VM console

### Issue: Cloud-init timeout

**Solution:** Wait longer (up to 15 minutes) or check boot diagnostics in Azure Portal.

## Cleanup (Destroy Resources)

⚠️ **WARNING**: This will delete ALL resources including Kafka clusters and data!

```bash
terraform destroy -var-file='secret.tfvars'
```

Type `yes` when prompted.

## Next Steps

1. ✅ Configure Kafka exporters and monitoring
2. ✅ Set up Grafana dashboards
3. ✅ Configure alerting rules
4. ✅ Backup Terraform state file
5. ✅ Document access credentials securely
6. ✅ Set up automated backups for critical data

## Useful Commands Reference

```bash
# Show all outputs
terraform output

# Show specific output
terraform output control_public_ip

# List all resources
terraform state list

# Refresh state
terraform refresh

# Import existing resources
terraform import azurerm_resource_group.example /subscriptions/.../resourceGroups/...

# Format Terraform files
terraform fmt

# Validate and format
terraform fmt -check
```

## Support Resources

- **Cloud-init logs**: `/var/log/cloud-init-output.log` (on control node)
- **Terraform docs**: https://www.terraform.io/docs
- **Azure CLI docs**: https://docs.microsoft.com/cli/azure
- **Ansible docs**: https://docs.ansible.com

## Security Reminders

🔒 Never commit `secret.tfvars` to version control
🔒 Use strong SSH keys (ED25519, minimum 4096-bit RSA)
🔒 Restrict NSG access to known IP ranges in production
🔒 Rotate credentials regularly
🔒 Enable Azure Security Center monitoring
