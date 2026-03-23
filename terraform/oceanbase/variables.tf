variable "resource_group_location" {
  type        = string
  default     = "westus"
  description = "Azure region for OceanBase cluster deployment. Use regions supporting D8s_v5 VMs and Premium SSDs."
}

variable "resource_group_name" {
  type        = string
  default     = "oceanbase-cluster"
  description = "Name of the Azure resource group for OceanBase infrastructure."
}

variable "oceanbase_vm_zone" {
  type        = string
  default     = ""
  description = "Azure Availability Zone for OceanBase observer VMs (1, 2, or 3). Leave empty for regions without AZs."
}

variable "enable_availability_zones" {
  type        = bool
  default     = true
  description = "Enable Availability Zones for OceanBase observers for high availability."
}

variable "ARM_SUBSCRIPTION_ID" {
  description = "Azure subscription identifier used for deployment."
  type        = string
}

variable "oceanbase_instance_count" {
  description = "Number of OceanBase observer instances to provision (recommended: 3 for HA)."
  type        = number
  default     = 3
}

variable "oceanbase_vm_size" {
  description = "Azure VM size for OceanBase observers."
  type        = string
  default     = "Standard_D8s_v5"
}

variable "oceanbase_data_disk_size_gb" {
  description = "Size of data disk for OceanBase (GB)."
  type        = number
  default     = 500
}

variable "oceanbase_redo_disk_size_gb" {
  description = "Size of redo log disk for OceanBase (GB)."
  type        = number
  default     = 200
}

variable "ansible_run_id" {
  description = "String to force rerun of OceanBase/monitoring Ansible playbooks. Change value to trigger."
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file for VMs."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key file for Terraform provisioners."
  type        = string
  default     = "~/.ssh/id_rsa"
  sensitive   = true
}

variable "deploy_mode" {
  description = "Deployment mode. 'together' deploys with control node, 'separate' deploys standalone."
  type        = string
  default     = "separate"

  validation {
    condition     = contains(["together", "separate"], var.deploy_mode)
    error_message = "deploy_mode must be either 'together' or 'separate'."
  }
}

# OceanBase specific configurations
variable "oceanbase_cluster_name" {
  description = "Name of the OceanBase cluster"
  type        = string
  default     = "ob_cluster"
}

variable "oceanbase_root_password" {
  description = "Root password for OceanBase database"
  type        = string
  default     = "OceanBase#!123"
  sensitive   = true
}

variable "oceanbase_mysql_port" {
  description = "MySQL port for OceanBase observer"
  type        = number
  default     = 2881
}

variable "oceanbase_memory_limit" {
  description = "Memory limit for OceanBase observer (e.g., '8G', '16G')"
  type        = string
  default     = "8G"
}

variable "oceanbase_cpu_count" {
  description = "CPU count for OceanBase observer"
  type        = number
  default     = 8
}

# Network configuration
variable "oceanbase_vnet_name" {
  type        = string
  default     = "oceanbase-vnet"
  description = "Name of the Virtual Network hosting OceanBase infrastructure."
}

variable "oceanbase_subnet_name" {
  type        = string
  default     = "default"
  description = "Name of the subnet within the OceanBase VNet."
}

variable "use_existing_oceanbase_network" {
  type        = bool
  default     = false
  description = "Reuse an existing OceanBase VNet/subnet instead of creating new network resources."
}

variable "existing_oceanbase_vnet_resource_group_name" {
  type        = string
  default     = ""
  description = "Resource group containing the existing OceanBase VNet/subnet."
}

variable "oceanbase_nsg_name" {
  type        = string
  default     = "oceanbase-nsg"
  description = "Name of the Network Security Group for OceanBase infrastructure."
}

variable "oceanbase_nsg_id" {
  type        = string
  default     = ""
  description = "Optional existing NSG ID to attach to OceanBase NICs."
}

variable "enable_nat_gateway" {
  type        = bool
  default     = true
  description = "Create and attach a NAT gateway for OceanBase subnet outbound access."
}

variable "oceanbase_allowed_cidrs" {
  type        = list(string)
  default     = ["10.0.0.0/16"]
  description = "CIDR blocks allowed to reach OceanBase ports (2881-2882-2886)."
}

variable "ssh_allowed_cidrs" {
  type        = list(string)
  default     = ["10.0.0.0/16"]
  description = "CIDR blocks allowed to SSH to OceanBase VMs."
}

# Control network peering variables
variable "control_resource_group_name" {
  type        = string
  default     = "control-ob-rg"
  description = "Name of the resource group containing the control node VNet for VNet peering."
}

variable "control_vnet_name" {
  type        = string
  default     = "control-vnet"
  description = "Name of the control node Virtual Network for VNet peering."
}

variable "enable_vnet_peering" {
  type        = bool
  default     = true
  description = "Enable VNet peering between OceanBase VNet and control VNet."
}

variable "repository_name" {
  description = "Name of the repository directory."
  type        = string
  default     = "ecom-middleware-opsob"
}

variable "control_node_user" {
  description = "Username for the control node VM."
  type        = string
  default     = "azureadmin"
}
