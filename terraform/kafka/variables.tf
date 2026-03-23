variable "resource_group_location" {
  type        = string
  default     = "westus"
  description = "Azure region for Kafka cluster deployment (e.g., westus3, westus, eastus). Must support Premium SSD v2 and Dsv6 VMs."
}

variable "resource_group_name" {
  type        = string
  default     = "kafka-cluster"
  description = "Name of the Azure resource group that will host all Kafka cluster infrastructure resources (VNet, subnets, VMs, NSG, NAT gateway, etc.)."
}

variable "kafka_vm_zone" {
  type        = string
  default     = ""
  description = "Azure Availability Zone for Kafka broker VMs (1, 2, or 3). Leave empty for regions without AZs (e.g., westus, northcentralus). Use zone-enabled regions for HA: wwestus3, westus, eastus, westus3, etc."
}

variable "enable_availability_zones" {
  type        = bool
  default     = true
  description = "Enable Availability Zones for Kafka brokers. Set to false for regions without AZs (westus, northcentralus, etc.). When false, kafka_vm_zone is ignored."
}

variable "ARM_SUBSCRIPTION_ID" {
  description = "Azure subscription identifier used for deployment."
  type        = string
}

variable "kafka_vms_name" {
  type        = string
  default     = "kafka-brokers"
  description = "Name prefix assigned to the Kafka broker virtual machines."
}

variable "kafka_admin_username" {
  type        = string
  default     = "rockyadmin"
  description = "Admin username provisioned on the Kafka broker instances."
}

variable "kafka_instance_count" {
  type        = number
  default     = 6  # Updated to 6 brokers
  description = "Number of Kafka broker instances to provision in the scale set."
}

variable "kafka_vm_size" {
  type        = string
  default     = "Standard_D8s_v6"  # Use D8s v6 per deployment requirement
  description = "Azure compute SKU for Kafka brokers (x64, Premium SSD v2 capable in most regions)."
}

variable "kafka_data_disk_size_gb" {
  type        = number
  default     = 1024  # Changed from 256 to get P30 tier (5000 IOPS, 200 MB/s)
  description = "Capacity, in GiB, of the Premium SSD data disk attached to each broker instance."
}

variable "use_premium_v2_disks" {
  type        = bool
  default     = false
  description = "Use PremiumV2_LRS disks with custom IOPS/throughput. Requires VMs in availability zones. Set to false for regions without zones (uses Premium_LRS instead)."
}

variable "kafka_data_disk_iops" {
  type        = number
  default     = 3000
  description = "Provisioned IOPS for Premium SSD v2 data disk (3000-80000, must be >= 3 IOPS per GiB). Only used when use_premium_v2_disks=true."
}

variable "kafka_data_disk_throughput_mbps" {
  type        = number
  default     = 125
  description = "Provisioned throughput (MB/s) for Premium SSD v2 data disk (125-1200, must be >= 0.25 MB/s per provisioned IOPS). Only used when use_premium_v2_disks=true."
}

# Bump this value (any non-empty string) to force the Ansible launch null_resource to re-run.
variable "ansible_run_id" {
  type        = string
  default     = ""
  description = "Change to trigger rerun of ansible playbooks after Kafka VM provisioning."
}

# Network resource naming variables
variable "kafka_vnet_name" {
  type        = string
  default     = "kafka-vnet"
  description = "Name of the Virtual Network hosting Kafka infrastructure."
}

variable "kafka_subnet_name" {
  type        = string
  default     = "default"
  description = "Name of the subnet within the Kafka VNet where broker VMs are deployed."
}

variable "use_existing_kafka_network" {
  type        = bool
  default     = false
  description = "Reuse an existing Kafka VNet/subnet instead of creating new network resources."
}

variable "existing_kafka_vnet_resource_group_name" {
  type        = string
  default     = ""
  description = "Resource group containing the existing Kafka VNet/subnet (defaults to resource_group_name when empty)."
}

variable "kafka_nsg_name" {
  type        = string
  default     = "kafka-nsg"
  description = "Name of the Network Security Group managing inbound/outbound traffic for Kafka infrastructure."
}

variable "kafka_allowed_cidrs" {
  type        = list(string)
  default     = ["10.0.0.0/16"]
  description = "CIDR blocks allowed to reach Kafka broker listeners (9092/9093/9094), ZooKeeper ports (2181/2888/3888), and monitoring ports (9308/9100)."
}

variable "ssh_allowed_cidrs" {
  type        = list(string)
  default     = ["10.0.0.0/16"]
  description = "CIDR blocks allowed to SSH to Kafka brokers/control node managed by this module."
}

variable "kafka_nat_ip_name" {
  type        = string
  default     = "kafka-nat-ip"
  description = "Name of the public IP address for the NAT gateway."
}

variable "kafka_nat_gateway_name" {
  type        = string
  default     = "kafka-nat-gateway"
  description = "Name of the NAT gateway for outbound internet connectivity."
}

variable "enable_kafka_nat_gateway" {
  type        = bool
  default     = false
  description = "Create and attach a NAT gateway for outbound access. Disable when the existing subnet already has outbound access configured."
}

variable "is_public" {
  type        = bool
  default     = false
  description = "Expose Kafka brokers with public IPs. When true: creates Static public IPs per broker and disables NAT gateway. When false: keeps brokers private with NAT gateway for outbound access (recommended for production). Cannot be true with enable_kafka_nat_gateway simultaneously."
}

variable "kafka_nsg_id" {
  type        = string
  default     = ""
  description = "Optional existing NSG ID to associate with Kafka NICs. When set, the module will use this NSG instead of creating/attaching its own."
}

# Control network peering variables
variable "control_resource_group_name" {
  type        = string
  default     = "control-rg"
  description = "Name of the resource group containing the control node VNet for VNet peering."
}

variable "control_vnet_name" {
  type        = string
  default     = "control-vnet"
  description = "Name of the control node Virtual Network for VNet peering with Kafka VNet."
}

variable "enable_vnet_peering" {
  type        = bool
  default     = false
  description = "Enable VNet peering between Kafka VNet and control VNet for Ansible connectivity."
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file for VMs. Defaults to ~/.ssh/id_rsa.pub. Can be overridden with custom key path."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "repository_name" {
  description = "Name of the repository directory. Used to construct full paths for Ansible working directories."
  type        = string
  default     = "ecom-middleware-ops"
}

variable "control_node_user" {
  description = "Username for the control node VM. Used to construct home directory paths."
  type        = string
  default     = "azureadmin"
}

variable "ansible_venv_path" {
  description = "Path to Ansible virtual environment on control node. Defaults to /home/{control_node_user}/ansible-venv."
  type        = string
  default     = ""  # Will be computed from control_node_user if empty
}

variable "repository_base_dir" {
  description = "Base directory path where repository is cloned on control node. Defaults to /home/{control_node_user}/{repository_name}."
  type        = string
  default     = ""  # Will be computed from control_node_user and repository_name if empty
}