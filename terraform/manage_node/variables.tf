variable "resource_group_location" {
  default     = "westus"
  description = "Location of the resource group."
}

variable "resource_group_name" {
  default     = "control_rg"
  description = "Resource group name for the control node."
}

variable "kafka_resource_group_name" {
  type        = string
  default     = "kafka-cluster"
  description = "Resource group name for Kafka cluster infrastructure (separate from control node)."
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

# Kafka network configuration
variable "use_existing_kafka_network" {
  type        = bool
  default     = false
  description = "Reuse an existing Kafka VNet/subnet instead of creating a new one in the kafka module."
}

variable "existing_kafka_vnet_resource_group_name" {
  type        = string
  default     = ""
  description = "Resource group containing the existing Kafka VNet/subnet (defaults to kafka_resource_group_name when empty)."
}

variable "kafka_vnet_name" {
  type        = string
  default     = "kafka-vnet"
  description = "Kafka VNet name passed into the kafka module / script."
}

variable "kafka_subnet_name" {
  type        = string
  default     = "default"
  description = "Kafka subnet name passed into the kafka module / script."
}

variable "enable_kafka_nat_gateway" {
  type        = bool
  default     = true
  description = "Create and attach a NAT gateway for Kafka subnet outbound access (disable when an existing subnet already has outbound access configured)."
}

variable "kafka_nsg_id" {
  type        = string
  default     = ""
  description = "Optional existing NSG ID to attach to Kafka NICs (overrides module-created NSG when set)."
}

variable "enable_vnet_peering" {
  type        = bool
  default     = true
  description = "Enable VNet peering between control and Kafka VNets. Disable when both live in the same VNet/subnet."
}

variable "kafka_vm_zone" {
  type        = string
  default     = ""
  description = "Azure Availability Zone for Kafka broker VMs (1, 2, or 3). Leave empty for regions without AZs (e.g., westus, northcentralus)."
}

variable "enable_availability_zones" {
  type        = bool
  default     = true
  description = "Enable Availability Zones for Kafka brokers. Set to false for regions without AZs (westus, northcentralus, etc.)."
}

variable "ARM_SUBSCRIPTION_ID" {
  description = "subscription id"
  type        = string
}

variable "kafka_instance_count" {
  description = "Number of Kafka broker instances to provision in the VMSS."
  type        = number
  default     = 3
}

variable "kafka_data_disk_iops" {
  description = "Provisioned IOPS for Kafka data disk (Premium SSD v2)."
  type        = number
  default     = 3000
}

variable "kafka_data_disk_throughput_mbps" {
  description = "Provisioned throughput (MB/s) for Kafka data disk (Premium SSD v2)."
  type        = number
  default     = 125
}

variable "kafka_vm_size" {
  description = "Azure VM size for Kafka brokers."
  type        = string
  default     = "Standard_D8s_v5"
}

variable "control_vm_size" {
  description = "Azure VM size for control node (must be available in the chosen region)."
  type        = string
  default     = "Standard_D8ls_v6"
}

variable "ansible_run_id" {
  description = "String to force rerun of Kafka/monitoring Ansible playbooks. Change value to trigger."
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file for VMs. Defaults to ~/.ssh/id_rsa.pub. Can be overridden with custom key path."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key file for Terraform provisioners. Defaults to ~/.ssh/id_rsa. Can be overridden with custom key path."
  type        = string
  default     = "~/.ssh/id_rsa"
  sensitive   = true
}

variable "deploy_mode" {
  description = "Deployment mode for Kafka cluster. 'together' deploys control node + initiates Kafka deployment. 'separate' deploys control node only (manual Kafka deployment via SSH)."
  type        = string
  default     = "together"

  validation {
    condition     = contains(["together", "separate"], var.deploy_mode)
    error_message = "deploy_mode must be either 'together' or 'separate'."
  }
}
