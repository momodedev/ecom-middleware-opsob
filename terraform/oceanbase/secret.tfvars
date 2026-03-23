# Azure Subscription Configuration
ARM_SUBSCRIPTION_ID = "8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b"

# Resource Group Configuration - SAME AS CONTROL NODE
resource_group_name       = "control-ob-rg"
resource_group_location   = "westus"

# OceanBase Cluster Configuration
oceanbase_instance_count    = 3  # Recommended: 3 nodes for high availability
oceanbase_vm_size           = "Standard_D8s_v6"  # Updated to v6 for latest generation
oceanbase_data_disk_size_gb = 500
oceanbase_redo_disk_size_gb = 200

# OceanBase Database Parameters
oceanbase_cluster_name      = "ob_cluster"
oceanbase_root_password     = "OceanBase#!123"
oceanbase_memory_limit      = "8G"
oceanbase_cpu_count         = 8     # Match D8s_v6 (8 vCPUs)

# Network Configuration
oceanbase_vnet_name         = "oceanbase-vnet"
oceanbase_subnet_name       = "default"
enable_nat_gateway          = true

# High Availability Configuration
enable_availability_zones   = true
oceanbase_vm_zone           = ""  # Leave empty for automatic zone distribution

# VNet Peering (for Ansible deployment from control node)
enable_vnet_peering         = true
control_resource_group_name = "control-ob-rg"  # Same RG as control node
control_vnet_name           = "control-ob-vnet"

# Deployment Mode
deploy_mode                 = "together"  # Deploy together with control node

# SSH Key Configuration
# Using the newly generated key for OceanBase deployment
ssh_public_key_path         = "/home/azureadmin/.ssh/oceanbase_deploy.pub"
ssh_private_key_path        = "/home/azureadmin/.ssh/oceanbase_deploy"

# Allowed CIDR Blocks (update with your network)
oceanbase_allowed_cidrs     = ["10.0.0.0/8"]
ssh_allowed_cidrs           = ["10.0.0.0/8"]

# Repository Configuration
repository_name             = "ecom-middleware-opsob"
control_node_user           = "azureadmin"
