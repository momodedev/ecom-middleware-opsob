# Azure Subscription
ARM_SUBSCRIPTION_ID = "8d6bd1eb-ae31-4f2c-856a-0f8e47115c4b"

# Resource group & location
resource_group_name   = "rds-prod"
create_resource_group = false
location              = "westus"

# VM
vm_name = "vm-ob-standalone"
vm_size = "Standard_D16s_v6" # 16 vCPU / 64 GiB

# OS user created by Azure
admin_username = "azureadmin"

# Dedicated OceanBase process user (created by cloud-init)
ob_admin_username = "admin"

# Disks
os_disk_size_gb   = 128
data_disk_size_gb = 500
redo_disk_size_gb = 500

# SSH keys
ssh_public_key_path  = "~/.ssh/id_rsa.pub"
ssh_private_key_path = "~/.ssh/id_rsa"

# OceanBase parameters
ob_cluster_name  = "ob_standalone"
ob_memory_limit  = "50G"            # leave ~14 GiB headroom on a 64 GiB VM
ob_root_password = "OceanBase#!123" # CHANGE before production use
