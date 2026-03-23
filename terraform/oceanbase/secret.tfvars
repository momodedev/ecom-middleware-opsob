# Azure Subscription Configuration
ARM_SUBSCRIPTION_ID = "8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b"

# Resource Group Configuration
resource_group_name       = "oceanbase-cluster"
resource_group_location   = "westus"

# OceanBase Cluster Configuration
oceanbase_instance_count    = 3  # Recommended: 3 nodes for high availability
oceanbase_vm_size           = "Standard_D8s_v5"
oceanbase_data_disk_size_gb = 500
oceanbase_redo_disk_size_gb = 200

# OceanBase Database Parameters
oceanbase_cluster_name      = "ob_cluster"
oceanbase_root_password     = "OceanBase#!123"  # Change to strong password!
oceanbase_memory_limit      = "8G"
oceanbase_cpu_count         = 8

# Network Configuration
oceanbase_vnet_name         = "oceanbase-vnet"
oceanbase_subnet_name       = "default"
enable_nat_gateway          = true

# High Availability Configuration
enable_availability_zones   = true
oceanbase_vm_zone           = ""  # Leave empty for automatic zone distribution

# VNet Peering (for Ansible deployment from control node)
enable_vnet_peering         = true
control_resource_group_name = "control-ob-rg"
control_vnet_name           = "control-vnet"

# Deployment Mode
deploy_mode                 = "separate"  # or "together" with control node

# SSH Key Configuration
ssh_public_key_path         = "~/.ssh/id_ed25519.pub"
ssh_private_key_path        = "~/.ssh/id_ed25519"

# Allowed CIDR Blocks (update with your network)
oceanbase_allowed_cidrs     = ["10.0.0.0/8"]
ssh_allowed_cidrs           = ["10.0.0.0/8"]

# Repository Configuration
repository_name             = "ecom-middleware-opsob"
control_node_user           = "azureadmin"
