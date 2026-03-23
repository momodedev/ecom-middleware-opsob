############### RG #################
# Validation: is_public and enable_kafka_nat_gateway are mutually exclusive
terraform {
  required_version = ">= 1.0"
}

# Prevent conflicting configuration
resource "terraform_data" "validate_config" {
  input = var.is_public && var.enable_kafka_nat_gateway ? "ERROR: Cannot set both is_public=true and enable_kafka_nat_gateway=true. Choose one: public IPs (is_public=true) OR NAT gateway (enable_kafka_nat_gateway=true)." : "OK"
  
  lifecycle {
    precondition {
      condition     = !(var.is_public && var.enable_kafka_nat_gateway)
      error_message = "CONFIGURATION ERROR: is_public and enable_kafka_nat_gateway cannot both be true. Choose: is_public=true for public brokers, OR enable_kafka_nat_gateway=true for NAT-based outbound access, but not both."
    }
  }
}

data azurerm_subscription "current" { }

# Reuse existing RG when told to; otherwise create
data "azurerm_resource_group" "existing" {
  count = var.use_existing_kafka_network ? 1 : 0
  name  = var.resource_group_name
}

resource "azurerm_resource_group" "example" {
  count    = var.use_existing_kafka_network ? 0 : 1
  location = var.resource_group_location
  name     = var.resource_group_name
}

resource "azurerm_virtual_network" "kafka" {
  count               = var.use_existing_kafka_network ? 0 : 1
  name                = var.kafka_vnet_name
  resource_group_name = local.kafka_rg_name
  location            = local.kafka_rg_location
  address_space       = ["172.16.0.0/16"]
}

data "azurerm_virtual_network" "kafka" {
  count               = var.use_existing_kafka_network ? 1 : 0
  name                = var.kafka_vnet_name
  resource_group_name = var.existing_kafka_vnet_resource_group_name != "" ? var.existing_kafka_vnet_resource_group_name : var.resource_group_name
}

resource "azurerm_subnet" "kafka" {
  count                = var.use_existing_kafka_network ? 0 : 1
  name                 = var.kafka_subnet_name
  resource_group_name  = local.kafka_rg_name
  virtual_network_name = azurerm_virtual_network.kafka[0].name
  address_prefixes     = ["172.16.1.0/24"]
}

data "azurerm_subnet" "kafka" {
  count                = var.use_existing_kafka_network ? 1 : 0
  name                 = var.kafka_subnet_name
  virtual_network_name = var.kafka_vnet_name
  resource_group_name  = var.existing_kafka_vnet_resource_group_name != "" ? var.existing_kafka_vnet_resource_group_name : var.resource_group_name
}

locals {
  kafka_rg_name      = var.use_existing_kafka_network ? data.azurerm_resource_group.existing[0].name : azurerm_resource_group.example[0].name
  kafka_rg_location  = var.use_existing_kafka_network ? data.azurerm_resource_group.existing[0].location : azurerm_resource_group.example[0].location
  kafka_network_rg   = var.existing_kafka_vnet_resource_group_name != "" ? var.existing_kafka_vnet_resource_group_name : var.resource_group_name
  kafka_vnet_id      = var.use_existing_kafka_network ? data.azurerm_virtual_network.kafka[0].id : azurerm_virtual_network.kafka[0].id
  kafka_subnet_id    = var.use_existing_kafka_network ? data.azurerm_subnet.kafka[0].id : azurerm_subnet.kafka[0].id
  kafka_nsg_id       = var.kafka_nsg_id != "" ? var.kafka_nsg_id : (!var.use_existing_kafka_network ? azurerm_network_security_group.example[0].id : null)
  kafka_existing_nsg_rg_name = var.kafka_nsg_id != "" ? split("/", var.kafka_nsg_id)[4] : null
  kafka_existing_nsg_name    = var.kafka_nsg_id != "" ? split("/", var.kafka_nsg_id)[8] : null
  attach_kafka_nsg   = var.kafka_nsg_id != "" || (!var.use_existing_kafka_network)
  kafka_nat_enabled  = var.enable_kafka_nat_gateway && !var.is_public
  
  # Computed paths for Ansible deployment
  computed_ansible_venv_path = var.ansible_venv_path != "" ? var.ansible_venv_path : "/home/${var.control_node_user}/ansible-venv"
  computed_repository_base   = var.repository_base_dir != "" ? var.repository_base_dir : "/home/${var.control_node_user}/${var.repository_name}"
  ansible_working_dir        = "${local.computed_repository_base}/ansible"
}

resource "azurerm_network_security_group" "example" {
  count               = var.kafka_nsg_id != "" || var.use_existing_kafka_network ? 0 : 1
  name                = var.kafka_nsg_name
  location            = local.kafka_rg_location
  resource_group_name = local.kafka_rg_name

  # SSH only from allowlist
  security_rule {
    name                       = "ssh-from-control"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.ssh_allowed_cidrs
    destination_address_prefix = "*"
  }

  # Kafka client port - internal cluster communication + control node access
  security_rule {
    name                       = "kafka-client"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9092"
    source_address_prefixes    = var.kafka_allowed_cidrs
    destination_address_prefix = "*"
  }

  # Kafka controller - internal cluster only
  security_rule {
    name                       = "kafka-controller"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9093"
    source_address_prefixes    = var.kafka_allowed_cidrs
    destination_address_prefix = "*"
  }

  # Kafka external listener - internal only
  security_rule {
    name                       = "kafka-external"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9094"
    source_address_prefixes    = var.kafka_allowed_cidrs
    destination_address_prefix = "*"
  }

  # Kafka exporter - monitoring from control node
  security_rule {
    name                       = "kafka-exporter"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9308"
    source_address_prefixes    = var.kafka_allowed_cidrs
    destination_address_prefix = "*"
  }

  # Node exporter - monitoring from control node
  security_rule {
    name                       = "node-exporter"
    priority                   = 150
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9100"
    source_address_prefixes    = var.kafka_allowed_cidrs
    destination_address_prefix = "*"
  }

  # ZooKeeper client port (Kafka brokers)
  security_rule {
    name                       = "zookeeper-client"
    priority                   = 160
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2181"
    source_address_prefixes    = var.kafka_allowed_cidrs
    destination_address_prefix = "*"
  }

  # ZooKeeper follower port (ensemble sync)
  security_rule {
    name                       = "zookeeper-peer"
    priority                   = 170
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2888"
    source_address_prefixes    = var.kafka_allowed_cidrs
    destination_address_prefix = "*"
  }

  # ZooKeeper leader election port
  security_rule {
    name                       = "zookeeper-election"
    priority                   = 180
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3888"
    source_address_prefixes    = var.kafka_allowed_cidrs
    destination_address_prefix = "*"
  }

  # Deny all other inbound traffic explicitly
  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Environment = "production"
    Component   = "kafka"
    Security    = "private-only"
  }
}

resource "azurerm_subnet_network_security_group_association" "example" {
  count                     = var.use_existing_kafka_network || var.kafka_nsg_id != "" ? 0 : 1
  subnet_id                 = azurerm_subnet.kafka[0].id
  network_security_group_id = azurerm_network_security_group.example[0].id
}

# Add ZooKeeper rules to an existing NSG when kafka_nsg_id is supplied.
resource "azurerm_network_security_rule" "existing_nsg_zookeeper_client" {
  count                       = var.kafka_nsg_id != "" ? 1 : 0
  name                        = "kafka-module-zookeeper-client"
  priority                    = 3130
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "2181"
  source_address_prefixes     = var.kafka_allowed_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = local.kafka_existing_nsg_rg_name
  network_security_group_name = local.kafka_existing_nsg_name
}

resource "azurerm_network_security_rule" "existing_nsg_zookeeper_peer" {
  count                       = var.kafka_nsg_id != "" ? 1 : 0
  name                        = "kafka-module-zookeeper-peer"
  priority                    = 3140
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "2888"
  source_address_prefixes     = var.kafka_allowed_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = local.kafka_existing_nsg_rg_name
  network_security_group_name = local.kafka_existing_nsg_name
}

resource "azurerm_network_security_rule" "existing_nsg_zookeeper_election" {
  count                       = var.kafka_nsg_id != "" ? 1 : 0
  name                        = "kafka-module-zookeeper-election"
  priority                    = 3150
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3888"
  source_address_prefixes     = var.kafka_allowed_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = local.kafka_existing_nsg_rg_name
  network_security_group_name = local.kafka_existing_nsg_name
}

# Data source to reference the existing control VNet
data "azurerm_virtual_network" "control" {
  count               = var.enable_vnet_peering ? 1 : 0
  name                = var.control_vnet_name
  resource_group_name = var.control_resource_group_name
}

# VNet peering: Kafka to Control
resource "azurerm_virtual_network_peering" "kafka_to_control" {
  count                        = var.enable_vnet_peering ? 1 : 0
  name                         = "kafka-to-control-peer"
  resource_group_name          = local.kafka_network_rg
  virtual_network_name         = var.kafka_vnet_name
  remote_virtual_network_id    = data.azurerm_virtual_network.control[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# VNet peering: Control to Kafka
resource "azurerm_virtual_network_peering" "control_to_kafka" {
  count                        = var.enable_vnet_peering ? 1 : 0
  name                         = "control-to-kafka-peer"
  resource_group_name          = var.control_resource_group_name
  virtual_network_name         = var.control_vnet_name
  remote_virtual_network_id    = local.kafka_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# ==================== NAT Gateway Configuration ====================
# NAT Gateway provides OUTBOUND internet access for Kafka brokers
# This allows VMs to download packages, updates, etc. without public IPs
# Inbound access is NOT possible through NAT - brokers remain private

resource "azurerm_public_ip" "example" {
  count               = local.kafka_nat_enabled ? 1 : 0
  name                = var.kafka_nat_ip_name
  location            = local.kafka_rg_location
  resource_group_name = local.kafka_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = {
    Environment = "production"
    Component   = "nat-gateway"
    Purpose     = "outbound-only"
  }
}

resource "azurerm_nat_gateway" "example" {
  count                  = local.kafka_nat_enabled ? 1 : 0
  name                   = var.kafka_nat_gateway_name
  location               = local.kafka_rg_location
  resource_group_name    = local.kafka_rg_name
  sku_name               = "Standard"
  idle_timeout_in_minutes = 10
  
  tags = {
    Environment = "production"
    Component   = "nat-gateway"
    Purpose     = "outbound-internet-access"
  }
}

resource "azurerm_nat_gateway_public_ip_association" "example" {
  count               = local.kafka_nat_enabled ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.example[0].id
  public_ip_address_id = azurerm_public_ip.example[0].id
}

resource "azurerm_subnet_nat_gateway_association" "example" {
  count         = (local.kafka_nat_enabled && !var.use_existing_kafka_network) ? 1 : 0
  subnet_id      = local.kafka_subnet_id
  nat_gateway_id = azurerm_nat_gateway.example[0].id
}
