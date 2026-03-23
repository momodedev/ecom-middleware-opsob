# Azure Subscription Configuration
ARM_SUBSCRIPTION_ID = "8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b"

# Resource Group Configuration
resource_group_name       = "control-ob-rg"
resource_group_location   = "westus"

# Control Network Configuration
# Set use_existing_control_network to true if using existing VNet/subnet
use_existing_control_network = false
control_vnet_name            = "control-ob-vnet"
control_subnet_name          = "control-ob-subnet"
control_nsg_name             = "control-ob-nsg"

# Or use existing NSG (uncomment and provide NSG ID if needed)
# control_nsg_id = "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/YOUR_RG/providers/Microsoft.Network/networkSecurityGroups/YOUR_NSG"

# VM Configuration
control_vm_size = "Standard_D8ls_v6"

# SSH Configuration
# SSH port for accessing the control node
control_ssh_port = 6666

# SSH key paths (defaults shown below, update if using custom keys)
# ssh_public_key_path = "~/.ssh/id_rsa.pub"
# ssh_private_key_path = "~/.ssh/id_rsa"

# OceanBase Cluster Configuration
oceanbase_resource_group_name           = "oceanbase-ob-cluster"
oceanbase_vnet_name                     = "oceanbase-ob-vnet"
oceanbase_subnet_name                   = "default"
oceanbase_instance_count                = 3
oceanbase_vm_size                       = "Standard_D8s_v5"
oceanbase_data_disk_size_gb             = 500
oceanbase_redo_disk_size_gb             = 200

# OceanBase Specific Settings
oceanbase_cluster_name                  = "ob_cluster"
oceanbase_root_password                 = "OceanBase#!123"
oceanbase_memory_limit                  = "8G"
oceanbase_cpu_count                     = 8

# Network Settings
enable_oceanbase_nat_gateway      = true
enable_vnet_peering               = true
enable_availability_zones         = true
oceanbase_vm_zone                 = ""

# Existing Network Settings (if applicable)
# existing_oceanbase_vnet_resource_group_name = ""
# oceanbase_nsg_id = ""

# Deployment Mode
# Options: "together" (deploy control + OceanBase) or "separate" (control only)
deploy_mode = "together"

# Ansible Run ID (change to force re-run of playbooks)
ansible_run_id = ""
