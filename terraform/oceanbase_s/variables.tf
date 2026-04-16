variable "ARM_SUBSCRIPTION_ID" {
  description = "Azure subscription ID."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group for OceanBase standalone resources."
  type        = string
  default     = "rds-prod"
}

variable "create_resource_group" {
  description = "Create the resource group if it does not already exist. Keep false for existing RGs like rds-prod."
  type        = bool
  default     = false
}

variable "location" {
  description = "Azure region for deployment. Choose a region that supports Standard_D16s_v6."
  type        = string
  default     = "westus"
}

variable "vm_name" {
  description = "Name of the OceanBase standalone VM."
  type        = string
  default     = "vm-ob-standalone"
}

variable "admin_username" {
  description = "OS-level admin user created by Azure."
  type        = string
  default     = "azureadmin"
}

variable "ob_admin_username" {
  description = "Dedicated OS user that runs OceanBase processes (created by cloud-init)."
  type        = string
  default     = "admin"
}

variable "vm_size" {
  description = "Azure VM size. Standard_D16s_v6 provides 16 vCPUs / 64 GiB."
  type        = string
  default     = "Standard_D16s_v6"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GiB."
  type        = number
  default     = 128
}

variable "data_disk_size_gb" {
  description = "Data disk size in GiB (mounted at /oceanbase/data)."
  type        = number
  default     = 500
}

variable "redo_disk_size_gb" {
  description = "Redo-log disk size in GiB (mounted at /oceanbase/redo)."
  type        = number
  default     = 500
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file used for the VM admin user."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key file used by Ansible and Terraform provisioners."
  type        = string
  default     = "~/.ssh/id_rsa"
  sensitive   = true
}

variable "ob_memory_limit" {
  description = "Memory limit passed to OceanBase (e.g. '50G'). Should leave ~14 GiB for OS."
  type        = string
  default     = "50G"
}

variable "ob_root_password" {
  description = "Root password for OceanBase sys tenant."
  type        = string
  default     = "OceanBase#!123"
  sensitive   = true
}

variable "ob_cluster_name" {
  description = "OceanBase cluster name used in OBD config."
  type        = string
  default     = "ob_standalone"
}
