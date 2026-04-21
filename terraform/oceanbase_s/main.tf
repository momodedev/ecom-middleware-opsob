# --------------------------------------------------------------------------- #
# Resource Group
# --------------------------------------------------------------------------- #
data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

resource "azurerm_resource_group" "rg" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
}

locals {
  rg_name     = var.create_resource_group ? azurerm_resource_group.rg[0].name : data.azurerm_resource_group.existing[0].name
  rg_location = var.create_resource_group ? azurerm_resource_group.rg[0].location : data.azurerm_resource_group.existing[0].location
}

# --------------------------------------------------------------------------- #
# Virtual Network & Subnet
# --------------------------------------------------------------------------- #
resource "azurerm_virtual_network" "vnet" {
  name                = "ob-standalone-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = local.rg_location
  resource_group_name = local.rg_name

  tags = { Component = "ob-standalone" }
}

resource "azurerm_subnet" "subnet" {
  name                 = "ob-standalone-subnet"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# --------------------------------------------------------------------------- #
# Network Security Group
# --------------------------------------------------------------------------- #
resource "azurerm_network_security_group" "nsg" {
  name                = "ob-standalone-nsg"
  location            = local.rg_location
  resource_group_name = local.rg_name

  # SSH – restrict source_address_prefix to your management IP in production
  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # OceanBase MySQL port (clients connect here)
  security_rule {
    name                       = "AllowOBMySQL"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2881"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # OceanBase RPC port (internal, kept restricted to VNet)
  security_rule {
    name                       = "AllowOBRPC"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2882"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # OBShell management port
  security_rule {
    name                       = "AllowOBShell"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2886"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  tags = { Component = "ob-standalone" }
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "nsg_subnet" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# --------------------------------------------------------------------------- #
# Public IP
# --------------------------------------------------------------------------- #
resource "azurerm_public_ip" "pip" {
  name                = "ob-standalone-pip"
  location            = local.rg_location
  resource_group_name = local.rg_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = { Component = "ob-standalone" }

  # Azure may inject provider-managed metadata (for example FirstPartyUsage)
  # and normalize zones. Ignore these to avoid destructive replacement.
  lifecycle {
    ignore_changes = [
      ip_tags,
      zones,
    ]
  }
}

# --------------------------------------------------------------------------- #
# Network Interface
# --------------------------------------------------------------------------- #
resource "azurerm_network_interface" "nic" {
  name                = "ob-standalone-nic"
  location            = local.rg_location
  resource_group_name = local.rg_name

  ip_configuration {
    name                          = "ob-standalone-ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }

  tags = { Component = "ob-standalone" }
}
