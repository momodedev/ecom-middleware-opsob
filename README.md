# Kafka Deployment on Azure using Ansible & Terraform

A complete infrastructure-as-code solution for deploying and managing Apache Kafka clusters on Azure. This project provides automated provisioning, configuration, monitoring, and operational management using Terraform and Ansible.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Configuration Variables](#configuration-variables)
- [Deployment Modes](#deployment-modes)
- [Directory Structure](#directory-structure)
- [Operations & Management](#operations--management)
- [Troubleshooting](#troubleshooting)

---

## Overview

This repository automates the entire lifecycle of Kafka infrastructure on Azure:

- **Infrastructure Provisioning**: Virtual networks, VMs, storage, and networking
- **Kafka Installation**: Multi-broker KRaft mode clusters (combined broker+controller architecture)
- **Monitoring**: Prometheus, Grafana, node exporters, and Kafka exporters
- **Operations**: Health checks, scaling (up/down), restarts, and graceful shutdowns
- **State Management**: Terraform state handling for existing resources

### Key Features

- ✅ **Flexible Deployment Modes**: Deploy everything together or control node separately
- ✅ **KRaft Mode**: Combined broker+controller nodes with dynamic quorum configuration
- ✅ **Intelligent Scaling**: Auto-detect VM sizes, safe scale-out and scale-down operations
- ✅ **Separate Resource Groups**: Control node and Kafka clusters in isolated resource groups
- ✅ **Private Networking**: Kafka brokers on private IPs with NAT gateway for security
- ✅ **Health Checks**: Comprehensive broker and cluster validation
- ✅ **Monitoring Stack**: Prometheus metrics, Grafana dashboards, and exporters
- ✅ **SSH Management**: Auto-authorization and host key management
- ✅ **Ansible Binary Detection**: Auto-detect Ansible in venv with fallbacks
- ✅ **VM Auto-Start**: Validation script auto-starts stopped VMs before deployment
- ✅ **State Recovery**: Import existing resources or clean up conflicts

---

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/ecom-middleware-ops.git
cd ecom-middleware-ops
```

### 2. Set Azure Credentials

```bash
az login

export ARM_SUBSCRIPTION_ID="your-subscription-id"
export ARM_TENANT_ID="your-tenant-id"
```

### 3. Control Node Deployment (Recommended for Production)

```bash
cd terraform/manage_node

# Create a secret.tfvars file with your configuration
cat > secret.tfvars <<EOF
ARM_SUBSCRIPTION_ID       = "8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b"
kafka_instance_count     = 3
deploy_mode              = "together"  # or "separate"
kafka_vm_size            = "Standard_D4as_v5"
resource_group_location  = "westus"
resource_group_name      = "kafka_t1"
kafka_resource_group_name = "kafka_t1"
control_vm_size          = "Standard_D4as_v5"
EOF

terraform init
terraform apply -var-file='secret.tfvars'
```

### 4. Verify the Deployment

```bash
# Get control node IP
CONTROL_IP=$(terraform output -raw control_public_ip)

# SSH to control node
ssh azureadmin@$CONTROL_IP

# Validate VMs are ready
cd ~/ecom-middleware-ops/ansible
source ~/ansible-venv/bin/activate
bash scripts/validate_vms_ready.sh kafka_t1 rockyadmin

# Run health check
./scripts/kafka_health_check.sh

# Check VM status in Azure
az vm list -g kafka_t1 --query "[].{Name:name, State:provisioningState, Power:powerState}" -o table
```

**Expected Output:**
- All VMs: `ProvisioningState: Succeeded`, `PowerState: running`
- SSH connectivity: All brokers respond
- Health check: 8/8 checks passing
- Monitoring: Grafana accessible at `http://<control_ip>:3000`
- All VMs: `ProvisioningState: Succeeded`, `PowerState: running`
- SSH connectivity: All brokers respond
- Health check: 8/8 checks passing

---

## Prerequisites

### Local Machine

- **Azure CLI**: `az login` configured with appropriate permissions
- **Terraform**: v1.x or later
- **SSH**: ssh-keygen, ssh-keyscan (usually pre-installed)

### Azure Subscription

Valid Azure subscription with permissions to create:
- Virtual Networks (VNet, subnets, NAT gateway)
- Virtual Machines (control node and Kafka brokers)
- Network Security Groups (NSGs) and Network Interfaces
- Azure Key Vault and secrets
- Public IPs and managed identities
- Role assignments (Contributor, Key Vault Secrets Officer)

### Required Environment Variables

```bash
export ARM_SUBSCRIPTION_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export ARM_TENANT_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

---

## Configuration Variables

### Core Variables (terraform/manage_node/variables.tf)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_group_name` | string | `"control_rg"` | Resource group name for control node |
| `kafka_resource_group_name` | string | `"kafka_t1"` | Resource group name for Kafka cluster (separate from control) |
| `resource_group_location` | string | `"westus"` | Azure region for both resource groups |
| `control_vm_size` | string | `"Standard_D4as_v5"` | Azure VM SKU for control node |
| `kafka_vm_size` | string | `"Standard_D8s_v5"` | Azure VM SKU for Kafka brokers |
| `kafka_instance_count` | number | `3` | Number of Kafka broker instances |
| `kafka_vm_zone` | string | `"1"` | Azure Availability Zone (1, 2, or 3) |
| `kafka_data_disk_iops` | number | `3000` | Provisioned IOPS for Kafka data disk (Premium SSD v2) |
| `kafka_data_disk_throughput_mbps` | number | `125` | Provisioned throughput (MB/s) for data disk |
| `ssh_public_key_path` | string | `"~/.ssh/id_rsa.pub"` | Path to SSH public key file |
| `ssh_private_key_path` | string | `"~/.ssh/id_rsa"` | Path to SSH private key file (sensitive) |
| `ARM_SUBSCRIPTION_ID` | string | - | Azure subscription ID |
| `ansible_run_id` | string | `""` | String to force Ansible playbook rerun |
| `deploy_mode` | string | `"together"` | Deployment mode: `"together"` or `"separate"` |

### Deploy Mode Configuration

The `deploy_mode` variable controls deployment behavior:

**Mode: `"together"` (Default)**
- Deploys control node infrastructure
- Automatically provisions Kafka cluster
- Runs Ansible playbooks for configuration
- Sets up monitoring stack (Prometheus + Grafana)
- **Use Case**: Full automated deployment, CI/CD pipelines

**Mode: `"separate"`**
- Deploys control node infrastructure only
- Skips Kafka cluster provisioning
- Customer manually triggers Kafka deployment via SSH
- **Use Case**: Manual staging, step-by-step validation, custom workflows

### Kafka Broker Network Configuration

The `is_public` variable controls how Kafka brokers are exposed:

**Public Brokers (`is_public=true`)**
- Each broker gets a Static Public IP
- Brokers are accessible from the internet
- NAT gateway is automatically disabled
- **Use Case**: Development, testing, external clients
- **Security**: Requires proper NSG rules to restrict inbound traffic

**Private Brokers (`is_public=false`, Default)**
- Brokers use only Private IPs
- NAT gateway provides outbound internet access (for package downloads, updates)
- Brokers NOT accessible from internet (protected)
- **Use Case**: Production, secure environments, internal-only clusters
- **Security**: Recommended for production deployments

**Important**: `is_public` and `enable_kafka_nat_gateway` are mutually exclusive. Set only one to `true`.

### Example Configuration (secret.tfvars)

```hcl
# Required
ARM_SUBSCRIPTION_ID       = "8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b"
deploy_mode              = "together"  # Change to "separate" for manual deployment

# Kafka cluster sizing
kafka_instance_count     = 3
kafka_vm_size            = "Standard_D4as_v5"
kafka_data_disk_iops     = 3000  # Optional, defaults to 3000
kafka_data_disk_throughput_mbps = 125  # Optional, defaults to 125

# Kafka broker network exposure (choose one approach)
is_public_kafka          = false  # Set to true for public IPs; false for private+NAT (default, production-recommended)

# Regional configuration
resource_group_location  = "westus"
resource_group_name      = "kafka_t1"
kafka_resource_group_name = "kafka_t1"
kafka_vm_zone            = "2"

# Control node
control_vm_size          = "Standard_D4as_v5"

# Deployment paths (optional, defaults shown)
# repository_name        = "ecom-middleware-ops"    # Repository directory name
# control_node_user      = "azureadmin"             # Control node username
# ansible_venv_path      = "/home/azureadmin/ansible-venv"  # Ansible venv location
# repository_base_dir    = "/home/azureadmin/ecom-middleware-ops"  # Repository base path

# SSH keys (optional, defaults to ~/.ssh/id_rsa[.pub])
# ssh_public_key_path    = "~/.ssh/custom_key.pub"
# ssh_private_key_path   = "~/.ssh/custom_key"
```

---

## Deployment Modes

### Mode 1: Together (Automated Full Stack)

**Behavior:**
```bash
terraform apply -var-file=secret.tfvars
# → Deploys control node
# → Auto-provisions Kafka brokers
# → Configures KRaft cluster
# → Deploys monitoring stack
# → Ready in ~10-15 minutes
```

**When to Use:**
- Production deployments with predictable configuration
- CI/CD pipelines
- Rapid environment provisioning
- Testing and development

---

### Mode 2: Separate (Manual Kafka Deployment)

**Behavior:**
```bash
terraform apply -var-file=secret.tfvars
# → Deploys control node ONLY
# → Stops at control node provisioning
# → Customer SSHs in manually
# → Customer runs Kafka deployment script
```

**When to Use:**
- Custom deployment workflows
- Step-by-step validation requirements
- Manual configuration adjustments before Kafka deployment
- Troubleshooting and experimentation

**Manual Deployment Steps:**
```bash
# 1. Deploy control node
cd terraform/manage_node
terraform apply -var-file=secret.tfvars

# 2. SSH to control node
CONTROL_IP=$(terraform output -raw control_public_ip)
ssh azureadmin@$CONTROL_IP

# 3. Deploy Kafka cluster from control node
cd ~/ecom-middleware-ops/terraform/kafka
terraform init
terraform plan -var-file='../manage_node/secret.tfvars'
terraform apply -var-file='../manage_node/secret.tfvars' -auto-approve

# 4. Configure Kafka brokers with Ansible
cd ~/ecom-middleware-ops/ansible
source ~/ansible-venv/bin/activate
ansible-playbook -i inventory/kafka_hosts playbooks/deploy_kafka_playbook.yaml

# 5. Validate deployment
./scripts/kafka_health_check.sh
```

---

## Kafka VM Provisioning

Kafka broker VMs are provisioned with a two-stage bootstrap process:

### Stage 1: Cloud-Init Bootstrap (Automated)
When Kafka VMs are created, cloud-init automatically:
- Installs system dependencies: Java 17, Python 3, git, curl, jq
- Creates required directories: `/opt/kafka`, `/data/kafka`
- Formats and mounts data disk (if attached)
- Sets up Python virtual environment for Ansible
- Configures system limits and kernel parameters for Kafka performance

**Cloud-init template:** [terraform/kafka/cloud-init.tpl](terraform/kafka/cloud-init.tpl)
- Executes on first boot (takes ~2 minutes)
- Logs to `/var/log/kafka-bootstrap-complete.log`

### Stage 2: Ansible Configuration (Remote)
After cloud-init completes, Ansible (running on the control node):
- Generates dynamic Kafka broker inventory
- Deploys Kafka binaries and configuration
- Enables KRaft consensus mode with controller quorum
- Sets up monitoring exporters (Kafka exporter, node exporter)
- Deploys Prometheus and Grafana stack

---

## Kafka Architecture: KRaft Combined Mode

### Controller Configuration

All Kafka brokers in this deployment run in **combined broker+controller mode**:

```yaml
# ansible/roles/kafka/defaults/main.yaml
kafka_process_roles: "broker,controller"
```

**What This Means:**
- Every broker serves dual roles: data broker + metadata controller
- No separate controller-only nodes required
- Controller quorum is dynamically built from all brokers
- Follows Apache Kafka KRaft best practices for small-to-medium clusters

### Dynamic Quorum Configuration

The `controller.quorum.voters` property is auto-generated from inventory:

```yaml
# ansible/playbooks/deploy_kafka_playbook.yaml (lines 42-48)
controller_quorum_voters: >-
  {% for host in groups['kafka'] %}
  {{ hostvars[host]['kafka_node_id'] }}@{{ hostvars[host]['ansible_host'] }}:9093
  {%- if not loop.last -%},{%- endif -%}
  {% endfor %}
```

**Example for 3-broker cluster:**
```properties
controller.quorum.voters=1@172.16.1.4:9093,2@172.16.1.5:9093,3@172.16.1.6:9093
```

### Verify Controller Status

```bash
# SSH to any broker or control node
ssh azureadmin@<control_ip>

# Check quorum status (from any broker IP)
/opt/kafka/bin/kafka-metadata-quorum.sh \
  --bootstrap-server 172.16.1.6:9092 \
  describe --status

# Expected output:
# ClusterId:              abc123...
# LeaderId:               1
# LeaderEpoch:            2
# HighWatermark:          500
# MaxFollowerLag:         0
# MaxFollowerLagTimeMs:   0
# CurrentVoters:          [1,2,3]
# CurrentObservers:       []
```

### Scaling and Controller Quorum

**Scale-Out (3→5 brokers):**
- New brokers added as broker+controller nodes
- `controller.quorum.voters` updated on all brokers: `1@...,2@...,3@...,4@...,5@...`
- All brokers restarted with new configuration
- Quorum automatically expands

**Scale-Down (5→3 brokers):**
- Target brokers safely decommissioned (partitions reassigned)
- `controller.quorum.voters` updated on remaining brokers: `1@...,2@...,3@...`
- Remaining brokers restarted with new configuration
- Removed broker VMs destroyed via Terraform

---

## Directory Structure

```
ecom-middleware-ops/
├── README.md                          # This file
├── terraform/
│   ├── kafka/                         # Kafka infrastructure
│   │   ├── provider.tf
│   │   ├── variables.tf
│   │   ├── vms.tf                     # Broker VM definitions
│   │   ├── vnet.tf                    # Network configuration
│   │   └── terraform.tfstate
│   └── manage_node/                   # Control node setup
│       ├── provider.tf
│       ├── main.tf
│       ├── variables.tf
│       ├── cloud-init.tpl               # Cloud-init bootstrap template
│       ├── secret.tfvars
│       └── terraform.tfvars.example
├── ansible/
│   ├── ansible.cfg                    # Ansible configuration
│   ├── inventory/
│   │   ├── inventory.ini              # Control node inventory
│   │   └── kafka_hosts                # Kafka broker inventory
│   ├── playbooks/
│   │   ├── kafka_maintenance.yml      # Kafka operational tasks
│   │   ├── deploy_kafka_playbook.yaml # Initial Kafka setup
│   │   ├── deploy_monitoring_playbook.yml
│   │   ├── scale_out_kafka_broker.yml # Broker scaling
│   │   ├── authorize_control_ssh.yml  # SSH key setup
│   │   └── check_kafka_status.yml
│   ├── roles/
│   │   ├── common/                    # Common utilities
│   │   │   └── node_exporter/         # System metrics exporter
│   │   ├── kafka/                     # Kafka broker setup
│   │   │   ├── tasks/main.yaml
│   │   │   ├── defaults/main.yaml
│   │   │   ├── templates/
│   │   │   │   ├── server.properties.j2
│   │   │   │   ├── kafka.service.j2
│   │   │   │   └── prometheus_kafka_targets.json.j2
│   │   │   └── kafka_exporter/        # Kafka metrics exporter
│   │   └── monitoring/                # Prometheus & Grafana
│   │       └── prometheus_grafana/
│   ├── scripts/
│   │   ├── manage_kafka_cluster.sh    # Main orchestration script
│   │   ├── kafka_health_check.sh      # Health validation
│   │   ├── scale_out_broker.sh        # Add new brokers
│   │   ├── test_broker_ssh.sh         # SSH connectivity test
│   │   ├── import_existing_brokers.sh # Terraform state recovery
│   │   ├── cleanup_duplicate_brokers.sh
│   │   └── ... (other utilities)
│   ├── templates/
│   │   └── prometheus_node_targets.json.j2
│   └── files/
│       └── dashboards/                # Grafana dashboards
```

---

## Deployment Methods

This section is replaced by [Deployment Modes](#deployment-modes) above.

The project now uses a control node deployment model with two modes:
- **Together Mode**: Full automated deployment (control node + Kafka cluster)
- **Separate Mode**: Manual deployment (control node only, manual Kafka trigger)

See [Deployment Modes](#deployment-modes) for complete documentation.

---

## Operations & Management

### 1. Cluster Health Check

```bash
# Check all brokers
./ansible/scripts/kafka_health_check.sh

# Check specific broker
./ansible/scripts/kafka_health_check.sh kafka-broker-01
```

**Output includes:**
- Kafka process status
- Port accessibility
- API versions
- KRaft quorum status
- Topic inventory
- Log errors
- Exporter metrics

### 2. Manage Kafka Cluster

The main orchestration script for cluster operations:

```bash
./ansible/scripts/manage_kafka_cluster.sh <operation> [--limit host]

# Start all brokers
./ansible/scripts/manage_kafka_cluster.sh start

# Stop all brokers gracefully
./ansible/scripts/manage_kafka_cluster.sh stop

# Restart brokers (apply config changes)
./ansible/scripts/manage_kafka_cluster.sh reload

# Limit operation to specific brokers
./ansible/scripts/manage_kafka_cluster.sh start --limit kafka-broker-01
./ansible/scripts/manage_kafka_cluster.sh reload --limit kafka-broker-0[1:3]
```

**Operations:**
- **start**: Start Kafka brokers, then Prometheus/Grafana/exporters
- **stop**: Stop monitoring stack, then gracefully stop brokers
- **reload**: Restart brokers to apply configuration changes

### 3. Scale Out Cluster (Add Brokers)

Add new brokers to the cluster with automatic VM size detection:

```bash
cd ansible

# Scale to 5 brokers (adds broker-4 and broker-5)
./scripts/scale_out_broker.sh \
  --subscription-id 8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b \
  --broker-count 5 \
  --resource-group kafka_t1 \
  --ansible-user rockyadmin

# Or add a specific broker
./scripts/scale_out_broker.sh \
  --subscription-id 8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b \
  --broker-name kafka_t1-broker-6 \
  --resource-group kafka_t1 \
  --ansible-user rockyadmin
```

**Process:**
1. Auto-detects VM size from existing brokers (no hardcoded sizes)
2. Provisions new broker VMs via Terraform
3. Authorizes SSH from control node
4. Installs Kafka, Java, and exporters
5. Configures KRaft mode with updated `controller.quorum.voters`
6. Restarts all brokers with new configuration
7. Runs health checks
8. Updates Prometheus targets

### 4. Scale Down Cluster (Remove Brokers)

Safely remove brokers with partition reassignment:

```bash
cd ansible

# Scale down to 3 brokers (removes highest node IDs)
./scripts/scale_down_broker.sh \
  --target-count 3 \
  --subscription-id 8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b \
  --resource-group kafka_t1 \
  --ansible-user rockyadmin
```

**Process:**
1. Identifies brokers to remove (highest node IDs first)
2. Reassigns all partitions away from target brokers
3. Waits for reassignment completion
4. Stops Kafka on target brokers
5. Updates `controller.quorum.voters` on remaining brokers
6. Restarts remaining brokers with new configuration
7. Validates cluster health
8. Provides Terraform destroy command for VM cleanup
9. Updates Ansible inventory

**Important:** This script MUST be run BEFORE reducing `kafka_instance_count` in Terraform.

### 4. SSH Connectivity Test

Verify SSH access to all brokers:

```bash
./ansible/scripts/test_broker_ssh.sh
```

Shows:
- SSH key status
- Host key validation
- Connectivity to all inventory hosts
- Permission issues

### 5. VM Readiness Validation

Check VM status and auto-start stopped VMs:

```bash
cd ansible
source ~/ansible-venv/bin/activate

# Validate all VMs in resource group
bash scripts/validate_vms_ready.sh kafka_t1 rockyadmin

# This script:
# - Checks VM power state
# - Auto-starts stopped VMs with 6 retries (~60s timeout)
# - Validates SSH connectivity
# - Reports VM readiness status
```

### 6. Monitoring

#### Access Grafana

```bash
# Get control node IP
terraform output -raw control_public_ip  # From manage_node/

# Open browser
open http://<control-ip>:3000
# Default: admin / admin
```

#### Query Prometheus

```bash
# Get control node IP
CONTROL_IP=$(terraform output -raw control_public_ip)

# Query example
curl "http://$CONTROL_IP:9090/api/v1/query?query=kafka_brokers"
```

#### Available Metrics

- `kafka_brokers`: Active brokers in cluster
- `kafka_controller_active_count`: Active controllers
- `kafka_topic_partitions`: Topic partition count
- `kafka_consumer_group_lag`: Consumer lag
- `node_cpu_seconds_total`: Host CPU metrics
- `node_memory_MemAvailable_bytes`: Host memory

---

## Terraform State Management

### Problem Scenarios

When scaling Kafka brokers, you may encounter this error:

```
Error: a resource with the ID ".../kafka_t1-broker-4" already exists - 
to be managed via Terraform this resource needs to be imported into the State.
```

This occurs when:
- Resources were created outside Terraform
- Terraform state file was lost/reset
- Previous scale-out created untracked resources

### Solution 1: Import Existing Resources (Recommended)

```bash
cd ansible/scripts

# Import brokers into state
./import_existing_brokers.sh \
  --subscription-id 8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b \
  --resource-group kafka_t1 \
  --broker-count 6

# Verify import
cd ../../terraform/kafka
terraform state list | grep kafka_brokers

# Review and apply
terraform plan
terraform apply -auto-approve
```

### Solution 2: Clean Up Conflicting Resources

```bash
cd ansible/scripts

# Delete conflicting brokers (destructive)
./cleanup_duplicate_brokers.sh \
  --subscription-id 8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b \
  --resource-group kafka_t1 \
  --broker-indices 4,5

# Recreate via Terraform
cd ../../terraform/kafka
terraform apply -auto-approve
```

### Solution 3: Manual Terraform Import

```bash
cd terraform/kafka

SUBSCRIPTION_ID="8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b"
RG="kafka_t1"

# Import broker VM
terraform import azurerm_linux_virtual_machine.kafka_brokers[4] \
  /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Compute/virtualMachines/kafka_t1-broker-4

# Import network interface
terraform import azurerm_network_interface.kafka_brokers[4] \
  /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Network/networkInterfaces/kafka_t1-broker-4-nic

# Import data disk
terraform import azurerm_managed_disk.kafka_data_disk[4] \
  /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Compute/disks/kafka_t1-broker-4-data
```

---

## Configuration Reference

### Kafka Defaults

**Location:** `ansible/roles/kafka/defaults/main.yaml`

```yaml
kafka_version: "3.6.0"
kafka_url: "https://archive.apache.org/dist/kafka/{{ kafka_version }}/kafka_2.13-{{ kafka_version }}.tgz"
kafka_workspace: "/opt/kafka"
kafka_home: "/opt"
kafka_data_dir: "/data/kafka"

kafka_heap_size: "-Xmx2G -Xms2G"
kafka_client_port: 9092
kafka_controller_port: 9093
kafka_external_port: 9094

kafka_exporter_version: "1.6.0"
kafka_exporter_port: 9308

kafka_node_id: 1  # Auto-assigned per broker
kafka_cluster_id: "auto-generated"
```

### Kafka Server Properties

Generated from template: `ansible/roles/kafka/templates/server.properties.j2`

Key configuration:
- **KRaft Mode**: Multi-broker consensus
- **Replication Factor**: 3 (configurable)
- **Min ISR**: 2 (configurable)
- **Log Retention**: 168 hours (7 days)
- **Log Segment**: 1 GB

---

## Troubleshooting

### VM Deployment Issues (Azure Throttling/Stuck VMs)

**Problem**: VMs get stuck during creation or fail to deploy

**Common Causes:**
1. **Azure quota limits** - Region has insufficient capacity
2. **VM SKU unavailable** - Newer SKUs not available in region
3. **Concurrent resource creation** - Azure throttles parallel VM creation
4. **Cloud-init timeout** - VMs still initializing when Ansible tries to connect
5. **Stopped VMs** - VMs in deallocated state blocking deployment

**Solutions:**

```bash
# 1. Check quota availability
az vm list-usage --location westus --query "[?contains(name.value, 'standardDSv5Family')]" -o table

# 2. Verify VM SKU availability in region
az vm list-skus --location westus --size Standard_D4 --all -o table

# 3. Use mature VM SKU (recommended)
# Edit terraform/manage_node/secret.tfvars:
kafka_vm_size = "Standard_D4as_v5"  # Instead of v6
control_vm_size = "Standard_D4as_v5"

# 4. Change region if needed
resource_group_location = "eastus2"  # Or weastus2, westeurope

# 5. Validate and auto-start VMs before deployment
cd ansible
source ~/ansible-venv/bin/activate
bash scripts/validate_vms_ready.sh kafka_t1 rockyadmin
# This script auto-starts stopped VMs with 6 retries (~60s timeout)
```

**Improvements Made:**
- ✅ Added 30-second delays between VM creations to prevent throttling
- ✅ Extended VM creation timeout to 45 minutes
- ✅ Automatic VM readiness validation with auto-start capability
- ✅ SSH connectivity retries with exponential backoff
- ✅ Ansible retry logic for failed deployments

### SSH Connection Issues

**Problem**: `Permission denied (publickey)`

```bash
# Check SSH key on control node
cat ~/.ssh/authorized_keys | grep control-node

# Regenerate key and re-authorize
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Re-run authorization playbook
ansible-playbook -i inventory/kafka_hosts playbooks/authorize_control_ssh.yml
```

### Kafka Broker Won't Start

```bash
# SSH to broker
ssh kafka-broker-01

# Check service logs
sudo journalctl -u kafka.service -n 50 -f

# Verify configuration
cat /opt/kafka/config/server.properties | grep -E "^[^#]"

# Check storage formatting
stat /data/kafka/meta.properties
```

### Health Check Failures

```bash
# Test broker connectivity
nc -zv 172.16.1.7 9092

# Test API versions (if Kafka CLI available locally)
/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092

# Test remote execution
ssh kafka-broker-01 '/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092'
```

### Systemd Daemon Reload Timeouts

**Problem**: `Failed to reload daemon: Method call timed out`

**Solution:**

```bash
# Rebuild systemd cache
sudo systemctl daemon-reload

# Restart the service explicitly
sudo systemctl restart kafka.service

# Check for errors
sudo systemctl status kafka.service
```

**Root Cause:** The `kafka_maintenance.yml` playbook has been updated to skip `daemon_reload` during the kafka_exporter start operation to avoid these timeouts. All shell commands now use `set -o pipefail` to ensure proper pipe handling.

### Ansible Binary Not Found

**Problem**: `ansible-playbook: command not found` during scale operations

**Cause**: Ansible installed in virtual environment but not in PATH

**Solutions:**

```bash
# 1. Activate virtual environment
source ~/ansible-venv/bin/activate

# 2. Run scale operations within activated venv
./ansible/scripts/scale_out_broker.sh --broker-count 5 ...

# 3. Or let scripts auto-detect (built-in feature)
# Scripts now auto-detect Ansible in venv with fallback logic:
# - Check if ansible/ansible-playbook are in PATH
# - Auto-detect ~/ansible-venv/bin/ if exists
# - Fall back to system binaries
```

**Improvements Made:**
- ✅ `scale_out_broker.sh` detects Ansible binary location automatically
- ✅ `scale_down_broker.sh` detects Ansible binary location automatically
- ✅ Fallback to system binaries if venv not found
- ✅ Clear error messages if Ansible not found anywhere

### Terraform State Conflicts

See [Terraform State Management](#terraform-state-management) section above.

---

## Advanced Usage

### Ansible Playbooks

Run individual playbooks for specific tasks:

```bash
# Deploy monitoring stack only
ansible-playbook -i inventory/inventory.ini playbooks/deploy_monitoring_playbook.yml

# Authorize SSH keys on new brokers
ansible-playbook -i inventory/kafka_hosts playbooks/authorize_control_ssh.yml

# Scale out new broker
ansible-playbook -i inventory/kafka_hosts playbooks/scale_out_kafka_broker.yml \
  -e "new_broker_host=kafka-broker-04"
```

### Terraform Variables

**For kafka deployment:**

```hcl
# terraform/kafka/terraform.tfvars
vm_count               = 3
broker_vm_size         = "Standard_D8s_v6"
kafka_broker_location  = "eastus2"
environment            = "prod"
```

**For control node:**

```hcl
# terraform/manage_node/secret.tfvars
resource_group_name      = "kafka_t1"
resource_group_location  = "eastus2"
```

#### Configurable Deployment Paths

All directory paths are configurable via Terraform variables, allowing flexible deployment across different environments:

**Default Configuration:**
- `repository_name`: `"ecom-middleware-ops"` - Repository directory name
- `control_node_user`: `"azureadmin"` - Username on control node
- `ansible_venv_path`: Auto-computed as `/home/{control_node_user}/ansible-venv`
- `repository_base_dir`: Auto-computed as `/home/{control_node_user}/{repository_name}`

**Custom Example:**
```hcl
# terraform/kafka/terraform.tfvars or secret.tfvars
repository_name     = "kafka-infra"
control_node_user   = "kafkaadmin"
ansible_venv_path   = "/opt/ansible-venv"
repository_base_dir = "/opt/kafka-infra"
```

**Shell Scripts:**
The Ansible scale scripts (`scale_out_broker.sh`, `scale_down_broker.sh`) automatically detect the Ansible virtual environment:
- First checks system PATH for `ansible-playbook`
- Falls back to `$ANSIBLE_VENV_PATH` environment variable
- Defaults to `/home/$USER/ansible-venv` if not set

**Override in shell:**
```bash
export ANSIBLE_VENV_PATH="/opt/ansible-venv"
./ansible/scripts/scale_out_broker.sh --broker-count 5 ...
```

### Custom Kafka Configuration

Modify broker properties via Ansible variables:

```bash
# Override in playbook
ansible-playbook -i inventory/kafka_hosts playbooks/deploy_kafka_playbook.yaml \
  -e "kafka_heap_size='-Xmx4G -Xms4G'" \
  -e "kafka_num_network_threads=16" \
  -e "kafka_num_io_threads=32"
```

---

## Execution Flow: Control Node Deployment

When you run `terraform apply -var-file='secret.tfvars'` in `terraform/manage_node/`:

### Stage 1: Infrastructure Creation (Terraform)
- Resource groups: separate for control node and Kafka cluster
- Networking: VNet, subnets, NSGs, NAT gateway for Kafka brokers
- Control VM (Rocky Linux 9, configurable VM size)
- Public IP for control node, private IPs for Kafka brokers
- Managed identity with Contributor role

### Stage 2: Provisioner Execution (on Control VM)
- System setup: Terraform, Ansible, Azure CLI, jq, Python3-venv
- SSH key generation (ED25519)
- Cloud-init bootstrap for VM initialization

### Stage 3: Kafka Deployment (conditional on deploy_mode)

**If deploy_mode="together":**
- Cloud-init completes automatically on control node startup
- Control node has Terraform, Ansible, and Azure CLI configured
- Manual SSH connection needed to trigger Kafka deployment
- Run Terraform to provision Kafka broker VMs
- Ansible configures brokers using KRaft combined mode
- Prometheus/Grafana monitoring stack configured
- Updates all brokers with dynamic `controller.quorum.voters`

**If deploy_mode="separate":**
- Provisioner execution skipped
- Cloud-init completes automatically on control node startup
- Customer manually SSHs to control node
- Customer runs Terraform and Ansible commands to deploy Kafka
- Full control over deployment timing and configuration

### Stage 4: Completion
- Kafka cluster ready on private network (if deploy_mode="together")
- Control node accessible via public IP
- Health checks passing (if Kafka deployed)
- Monitoring dashboard available at `http://<public-ip>:3000`

**Typical Deployment Time:** 
- Together mode: 10-15 minutes
- Separate mode: 5-7 minutes (control node only)

---

## SSH Management & Improvements

### Private IP Deployment Architecture

The Kafka cluster uses **private IPs only** for enhanced security:

- **Kafka Broker VMs**: No public IPs assigned (172.16.1.x range)
- **Control Node**: Single public IP for management access
- **NAT Gateway**: Provides outbound internet access for updates
- **VNet Peering**: Enables communication between control and Kafka VNets

**Network Flow:**
```
Internet → Control Node (Public IP) → VNet Peering → Kafka Brokers (Private IPs)
Kafka Brokers → NAT Gateway → Internet (for package downloads)
```

**Advantages:**
- Minimal attack surface (only control node exposed)
- Lower cost (one public IP vs. multiple)
- Better security compliance
- Simplified firewall rules

### Automatic Host Key Population

The deployment automatically:
- Uses `ssh-keyscan` to add broker host keys to `~/.ssh/known_hosts`
- Accepts ED25519 keys without manual intervention
- Prevents "REMOTE HOST IDENTIFICATION HAS CHANGED" errors
- Authorizes control node SSH key on all brokers

### SSH Configuration for Health Checks

```bash
SSH_OPTS=(
    "-o" "BatchMode=yes"
    "-o" "ConnectTimeout=5"
    "-o" "StrictHostKeyChecking=accept-new"
    "-o" "UserKnownHostsFile=~/.ssh/known_hosts"
)
```

This enables:
- Batch mode operations without user prompts
- Automatic acceptance of new host keys
- Remote command execution from any control node
- Graceful failure handling

---

## Health Check Enhancements

The health check script now includes:

- **Remote Execution Fallback**: Uses SSH to run Kafka CLI tools on brokers when not available locally
- **Broker Connectivity Checks**: Verifies API versions, quorum status, and topics
- **Log Analysis**: Checks for ERROR/FATAL messages in Kafka logs
- **Exporter Validation**: Confirms Kafka exporter metrics availability
- **8-Point Validation**: Comprehensive health assessment

**Sample Output:**
```
[1/8] Checking Kafka broker process...
✅ PASS: Kafka broker active on 172.16.1.7 via systemd

[2/8] Checking broker port accessibility...
✅ PASS: Broker port 9092 is accessible

[3/8] Checking broker API versions...
✅ PASS: Broker API versions accessible (via remote)

[4/8] Checking KRaft controller quorum...
✅ PASS: KRaft quorum status retrieved (via remote)

[5/8] Checking topics and partitions...
✅ PASS: No topics configured yet (cluster is clean)

[6/8] Checking broker logs for errors...
✅ PASS: No ERROR/FATAL messages in remote journal on 172.16.1.7

[7/8] Checking Kafka exporter...
✅ PASS: Remote exporter on 172.16.1.7:9308 is serving Kafka metrics
```

---

## Script Organization

Operational scripts are centralized in `ansible/scripts/`:

- **Cluster Management**: `manage_kafka_cluster.sh`, `kafka_health_check.sh`
- **Scaling**: `scale_out_broker.sh`, `test_broker_ssh.sh`
- **State Recovery**: `import_existing_brokers.sh`, `cleanup_duplicate_brokers.sh`
- **Utilities**: `kafka_cluster_id_generator.sh`, and other helper scripts

All scripts work from any directory and automatically navigate to the correct working directories.

---

## Contributing

When modifying scripts or playbooks:

1. Test on a development resource group first
2. Update documentation when adding features
3. Ensure SSH and state management tests pass
4. Validate Terraform and Ansible syntax

```bash
# Validate Terraform
cd terraform/kafka
terraform validate
terraform fmt -recursive

# Validate Ansible
ansible-playbook --syntax-check playbooks/*.yml

# Test SSH connectivity
./ansible/scripts/test_broker_ssh.sh

# Run health checks
./ansible/scripts/kafka_health_check.sh
```

---

## Support & Issues

For issues or questions:

1. Check [Troubleshooting](#troubleshooting) section
2. Review health check output: `./ansible/scripts/kafka_health_check.sh`
3. Check Kafka logs: `sudo journalctl -u kafka.service -n 100`
4. Review Terraform state: `terraform show | grep -A 10 kafka_brokers`
5. Verify systemd service status: `sudo systemctl status kafka.service`

---

## License

All scripts and configurations are proprietary. For authorization requests, contact the infrastructure team.

---

## Changelog

### January 2026 Updates

- **Deploy Mode Feature**: Added `deploy_mode` variable (`together` or `separate`) for flexible deployment strategies
- **Separate Resource Groups**: Control node and Kafka clusters in isolated resource groups
- **KRaft Combined Mode**: All brokers run as combined broker+controller nodes following best practices
- **Dynamic Controller Quorum**: Auto-generates `controller.quorum.voters` from inventory
- **Intelligent Scaling**: 
  - Scale-out with automatic VM size detection from existing brokers
  - Scale-down with safe partition reassignment and quorum reconfiguration
- **VM Auto-Start**: Validation script auto-starts stopped VMs before deployment (6 retries, ~60s timeout)
- **Ansible Binary Detection**: Auto-detect Ansible in venv with fallback to system binaries
- **SSH Management**: Auto-population of known_hosts, ED25519 key support
- **Health Checks**: Remote execution fallback for Kafka CLI tools when unavailable locally
- **Script Organization**: Operational scripts centralized in `ansible/scripts/`
- **Kafka Maintenance**: Fixed daemon-reload timeouts, stable restart operations with pipefail
- **State Management**: Import and recovery tools for existing brokers
- **Documentation**: Consolidated all docs into comprehensive README.md with deploy mode details
- **Systemd Fixes**: Removed daemon_reload from kafka_exporter start to prevent timeouts
- **Non-Interactive Init**: DEBIAN_FRONTEND=noninteractive for all package installations
- **Custom SSH Keys**: Configurable via `ssh_public_key_path` and `ssh_private_key_path` variables

example for deployment at 2026-01-20

export USE_EXISTING_KAFKA_NETWORK=true
export EXISTING_KAFKA_VNET_RESOURCE_GROUP_NAME="kafka_t1"
export KAFKA_VNET_NAME="vnet-t1"
export KAFKA_SUBNET_NAME="default"
export ENABLE_KAFKA_NAT_GATEWAY=false
export KAFKA_NSG_ID="/subscriptions/8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b/resourceGroups/kafka_t1/providers/Microsoft.Network/networkSecurityGroups/control-nsg"
export ENABLE_VNET_PEERING=false
export KAFKA_VM_ZONE="1"
export ENABLE_AVAILABILITY_ZONES=true
export USE_PREMIUM_V2_DISKS=true

cd ~/ecom-middleware-ops/terraform/kafka
terraform init
terraform plan -var-file=sub_id.tfvars
terraform apply -var-file=sub_id.tfvars -auto-approve

cd ~/ecom-middleware-ops/ansible
source ~/ansible-venv/bin/activate
ansible-playbook -i inventory/kafka_hosts playbooks/deploy_kafka_playbook.yaml

# Scale down or destroy
export KAFKA_VM_ZONE="1"
export ENABLE_AVAILABILITY_ZONES=true
export USE_PREMIUM_V2_DISKS=true

cd ~/ecom-middleware-ops/terraform/kafka
terraform destroy -var-file=sub_id.tfvars -auto-approve
```
