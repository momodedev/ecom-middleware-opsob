variable "subscription_id" {
  description = "Azure subscription ID used for deployment."
  type        = string
}

variable "location" {
  description = "Azure region for all networking resources."
  type        = string
  default     = "westus"
}

variable "resource_group_name" {
  description = "Resource group name for the CentOS performance test network."
  type        = string
  default     = "kafka-perf-v5-centos"
}

variable "vnet_name" {
  description = "Existing virtual network name."
  type        = string
  default     = "kafka-perf-v5-centos-vnet"
}

variable "subnet_name" {
  description = "Existing subnet name inside the VNet."
  type        = string
  default     = "kafka-perf-v5-centos-subnet"
}

variable "nsg_name" {
  description = "Existing Network Security Group name for Kafka test traffic."
  type        = string
  default     = "kafka-perf-v5-centos-nsg"
}

variable "allowed_cidr" {
  description = "CIDR allowed to access Kafka-related inbound ports."
  type        = string
  default     = "10.0.0.0/16"
}

variable "control_ssh_port" {
  description = "SSH port used by the control node."
  type        = number
  default     = 6666
}

# ── Kafka broker VM configuration ───────────────────────────────────────────

variable "kafka_instance_count" {
  description = "Number of CentOS 7.9 Kafka broker VMs to provision."
  type        = number
  default     = 3
}

variable "kafka_vm_size" {
  description = "Azure VM SKU for CentOS Kafka brokers (V5 family for perf test lane A)."
  type        = string
  default     = "Standard_D8s_v5"
}

variable "enable_availability_zones" {
  description = "Enable Availability Zones for broker VMs and disks. Required for Premium SSD v2 data disks."
  type        = bool
  default     = true
}

variable "kafka_vm_zone" {
  description = "Availability Zone for broker VMs/disks (for example: 1, 2, or 3)."
  type        = string
  default     = "1"

  validation {
    condition     = var.kafka_vm_zone == "" || can(regex("^(1|2|3)$", var.kafka_vm_zone))
    error_message = "kafka_vm_zone must be one of: 1, 2, 3, or empty string when zones are disabled."
  }
}

variable "kafka_admin_username" {
  description = "Admin username for CentOS broker VMs (also used as Ansible remote_user)."
  type        = string
  default     = "centosmadmin"
}

variable "kafka_data_disk_size_gb" {
  description = "Size in GiB of the Premium SSD data disk attached to each Kafka broker."
  type        = number
  default     = 1024
}

variable "use_premium_v2_disks" {
  description = "Use Premium SSD v2 disks with custom IOPS/throughput for broker data disks."
  type        = bool
  default     = true

  validation {
    condition     = !var.use_premium_v2_disks || (var.enable_availability_zones && var.kafka_vm_zone != "")
    error_message = "Premium SSD v2 requires zonal deployment. Set enable_availability_zones=true and kafka_vm_zone to 1, 2, or 3."
  }
}

variable "kafka_data_disk_iops" {
  description = "Provisioned IOPS for Premium SSD v2 data disk. Used when use_premium_v2_disks=true."
  type        = number
  default     = 3000
}

variable "kafka_data_disk_throughput_mbps" {
  description = "Provisioned throughput (MB/s) for Premium SSD v2 data disk. Used when use_premium_v2_disks=true."
  type        = number
  default     = 125
}

variable "is_public" {
  description = "Assign public IPs to brokers. Required when the new VNet is not peered to the control node VNet."
  type        = bool
  default     = true
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key uploaded to all broker VMs."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ansible_run_id" {
  description = "Change this string to force Ansible re-run without destroying/recreating VMs."
  type        = string
  default     = ""
}

# ── Control node / Ansible paths ────────────────────────────────────────────

variable "repository_name" {
  description = "Repository directory name on the control node."
  type        = string
  default     = "ecom-middleware-ops1"
}

variable "control_node_user" {
  description = "Admin username of the control node (used to compute Ansible venv and repo paths)."
  type        = string
  default     = "azureadmin"
}

variable "ansible_venv_path" {
  description = "Absolute path to Ansible venv on the control node. Leave empty to auto-compute."
  type        = string
  default     = ""
}

variable "repository_base_dir" {
  description = "Absolute path to the cloned repository on the control node. Leave empty to auto-compute."
  type        = string
  default     = ""
}

variable "enable_ansible_provisioner" {
  description = "Run null_resource local-exec to configure Kafka/monitoring. Set true only when applying from Linux control node with /bin/bash and ansible-venv."
  type        = bool
  default     = false
}

variable "manage_subnet_nsg_association" {
  description = "Whether Terraform should create/manage subnet-to-NSG association when missing on the existing subnet."
  type        = bool
  default     = true
}

variable "manage_network_security_rules" {
  description = "Create/manage NSG security rules in the existing NSG."
  type        = bool
  default     = true
}
