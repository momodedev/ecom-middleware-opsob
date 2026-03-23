variable "resource_group_location" {
  default     = "westus"
  description = "Location of the resource group."
}

variable "resource_group_name" {
  default     = "control_rg"
  description = "Resource group name for the control node."
}

variable "oceanbase_resource_group_name" {
  type        = string
  default     = "oceanbase-cluster"
  description = "Resource group name for OceanBase cluster infrastructure (separate from control node)."
}

# Control network naming variables
variable "control_vnet_name" {
  type        = string
  default     = "control-vnet"
  description = "Name of the Virtual Network hosting the management/control node."
}

variable "use_existing_control_network" {
  type        = bool
  default     = false
  description = "Reuse an existing control-plane VNet/subnet instead of creating new network resources."
}

variable "control_subnet_name" {
  type        = string
  default     = "control-subnet"
  description = "Name of the subnet within the control VNet for the management/control node."
}

variable "control_nsg_name" {
  type        = string
  default     = "control-nsg"
  description = "Name of the Network Security Group attached to the control subnet."
}

variable "control_ssh_port" {
  type        = number
  default     = 6666
  description = "SSH port for the control node Rocky Linux VM."
}

variable "control_nsg_id" {
  type        = string
  default     = ""
  description = "Optional existing NSG ID to use for control subnet. When set, the module will use this NSG instead of creating a new one."
}

# OceanBase network configuration
variable "use_existing_oceanbase_network" {
  type        = bool
  default     = false
  description = "Reuse an existing OceanBase VNet/subnet instead of creating a new one."
}

variable "existing_oceanbase_vnet_resource_group_name" {
  type        = string
  default     = ""
  description = "Resource group containing the existing OceanBase VNet/subnet."
}

variable "oceanbase_vnet_name" {
  type        = string
  default     = "oceanbase-vnet"
  description = "OceanBase VNet name."
}

variable "oceanbase_subnet_name" {
  type        = string
  default     = "default"
  description = "OceanBase subnet name."
}

variable "enable_oceanbase_nat_gateway" {
  type        = bool
  default     = true
  description = "Create and attach a NAT gateway for OceanBase subnet outbound access."
}

variable "oceanbase_nsg_id" {
  type        = string
  default     = ""
  description = "Optional existing NSG ID to attach to OceanBase NICs."
}

variable "enable_vnet_peering" {
  type        = bool
  default     = true
  description = "Enable VNet peering between control and OceanBase VNets."
}

variable "oceanbase_vm_zone" {
  type        = string
  default     = ""
  description = "Azure Availability Zone for OceanBase broker VMs (1, 2, or 3). Leave empty for regions without AZs."
}

variable "enable_availability_zones" {
  type        = bool
  default     = true
  description = "Enable Availability Zones for OceanBase brokers."
}

variable "ARM_SUBSCRIPTION_ID" {
  description = "subscription id"
  type        = string
}

variable "oceanbase_instance_count" {
  description = "Number of OceanBase observer instances to provision in the VMSS."
  type        = number
  default     = 3
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

variable "oceanbase_vm_size" {
  description = "Azure VM size for OceanBase observers."
  type        = string
  default     = "Standard_D8s_v5"
}

variable "control_vm_size" {
  description = "Azure VM size for control node."
  type        = string
  default     = "Standard_D8ls_v6"
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
  description = "Deployment mode for OceanBase cluster. 'together' deploys control node + initiates OceanBase deployment. 'separate' deploys control node only."
  type        = string
  default     = "together"

  validation {
    condition     = contains(["together", "separate"], var.deploy_mode)
    error_message = "deploy_mode must be either 'together' or 'separate'."
  }
}

# OceanBase specific configurations
variable "oceanbase_root_password" {
  description = "Root password for OceanBase database"
  type        = string
  default     = "OceanBase#!123"
  sensitive   = true
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

variable "oceanbase_cluster_name" {
  description = "Name of the OceanBase cluster"
  type        = string
  default     = "ob_cluster"
}
