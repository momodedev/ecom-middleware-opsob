data "azurerm_resource_group" "existing" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "existing" {
  name                = var.vnet_name
  resource_group_name = data.azurerm_resource_group.existing.name
}

data "azurerm_subnet" "existing" {
  name                 = var.subnet_name
  virtual_network_name = data.azurerm_virtual_network.existing.name
  resource_group_name  = data.azurerm_resource_group.existing.name
}

data "azurerm_network_security_group" "existing" {
  name                = var.nsg_name
  resource_group_name = data.azurerm_resource_group.existing.name
}

locals {
  foundation_rg_name     = data.azurerm_resource_group.existing.name
  foundation_rg_location = data.azurerm_resource_group.existing.location

  foundation_vnet_name = data.azurerm_virtual_network.existing.name
  foundation_subnet_id = data.azurerm_subnet.existing.id

  foundation_nsg_name = data.azurerm_network_security_group.existing.name
  foundation_nsg_id   = data.azurerm_network_security_group.existing.id
}

resource "azurerm_network_security_rule" "grafana_3000" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "3000"
  priority                    = 3200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "3000"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "prometheus_9090" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "9090"
  priority                    = 3210
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "9090"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "kafka_external_9094" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "allow-kafka-external"
  priority                    = 130
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "9094"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "kafka_exporter_9308" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "allow-kafka-exporter"
  priority                    = 140
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "9308"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "node_exporter_9100" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "allow-node-exporter"
  priority                    = 150
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "9100"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "control_ssh" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "control-ssh-${var.control_ssh_port}"
  priority                    = 3100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.control_ssh_port)
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "zookeeper_2181" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "kafka-module-zookeeper-client"
  priority                    = 3130
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "2181"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "zookeeper_2888" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "kafka-module-zookeeper-peer"
  priority                    = 3140
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "2888"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_network_security_rule" "zookeeper_3888" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "kafka-module-zookeeper-election"
  priority                    = 3150
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3888"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = local.foundation_rg_name
  network_security_group_name = local.foundation_nsg_name
}

resource "azurerm_subnet_network_security_group_association" "this" {
  count = (
    var.manage_subnet_nsg_association
    && data.azurerm_subnet.existing.network_security_group_id != local.foundation_nsg_id
  ) ? 1 : 0
  subnet_id                 = local.foundation_subnet_id
  network_security_group_id = local.foundation_nsg_id
}
