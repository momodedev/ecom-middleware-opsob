# OceanBase Virtual Network
resource "azurerm_virtual_network" "oceanbase" {
  name                = var.oceanbase_vnet_name
  resource_group_name = local.oceanbase_rg_name
  location            = local.oceanbase_rg_location
  address_space       = ["10.1.0.0/16"]

  tags = {
    Environment = "production"
    Component   = "oceanbase-network"
    ManagedBy   = "terraform"
  }

  lifecycle {
    ignore_changes = [address_space, tags]
  }
}

locals {
  oceanbase_vnet_name = azurerm_virtual_network.oceanbase.name
  oceanbase_vnet_id   = azurerm_virtual_network.oceanbase.id
}

# OceanBase Subnet
resource "azurerm_subnet" "oceanbase" {
  name                         = var.oceanbase_subnet_name
  resource_group_name          = local.oceanbase_rg_name
  virtual_network_name         = local.oceanbase_vnet_name
  address_prefixes             = ["10.1.1.0/24"]
  default_outbound_access_enabled = false

  lifecycle {
    ignore_changes = [address_prefixes]
  }
}

locals {
  oceanbase_subnet_name = azurerm_subnet.oceanbase.name
  oceanbase_subnet_id   = azurerm_subnet.oceanbase.id
}

# OceanBase Network Security Group
locals {
  oceanbase_nsg_id      = var.oceanbase_nsg_id != "" ? var.oceanbase_nsg_id : azurerm_network_security_group.oceanbase[0].id
  oceanbase_nsg_rg_name = var.oceanbase_nsg_id != "" ? split("/", var.oceanbase_nsg_id)[4] : local.oceanbase_rg_name
  oceanbase_nsg_name    = var.oceanbase_nsg_id != "" ? split("/", var.oceanbase_nsg_id)[8] : azurerm_network_security_group.oceanbase[0].name
  attach_oceanbase_nsg  = var.oceanbase_nsg_id != "" || true
}

resource "azurerm_network_security_group" "oceanbase" {
  count               = var.oceanbase_nsg_id != "" ? 0 : 1
  name                = var.oceanbase_nsg_name
  location            = local.oceanbase_rg_location
  resource_group_name = local.oceanbase_rg_name

  security_rule {
    name                       = "mysql"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.oceanbase_mysql_port)
    source_address_prefixes    = var.oceanbase_allowed_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "rpc"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2882"
    source_address_prefixes    = var.oceanbase_allowed_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "obshell"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2886"
    source_address_prefixes    = var.oceanbase_allowed_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ssh"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.ssh_allowed_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "monitoring"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9100,9308"
    source_address_prefixes    = var.oceanbase_allowed_cidrs
    destination_address_prefix = "*"
  }

  tags = {
    Environment = "production"
    Component   = "oceanbase-nsg"
    ManagedBy   = "terraform"
  }
}

resource "azurerm_subnet_network_security_group_association" "oceanbase" {
  count                     = local.attach_oceanbase_nsg ? 1 : 0
  subnet_id                 = local.oceanbase_subnet_id
  network_security_group_id = local.oceanbase_nsg_id
}

# NAT Gateway for outbound internet access
resource "azurerm_nat_gateway" "oceanbase" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "oceanbase-nat"
  location            = local.oceanbase_rg_location
  resource_group_name = local.oceanbase_rg_name

  tags = {
    Environment = "production"
    Component   = "oceanbase-nat"
    ManagedBy   = "terraform"
  }
}

resource "azurerm_subnet_nat_gateway_association" "oceanbase" {
  count             = var.enable_nat_gateway ? 1 : 0
  subnet_id         = local.oceanbase_subnet_id
  nat_gateway_id    = azurerm_nat_gateway.oceanbase[0].id
}

# VNet Peering with Control Node (for Ansible deployment)
resource "azurerm_virtual_network_peering" "oceanbase_to_control" {
  count                       = var.enable_vnet_peering && var.deploy_mode == "together" ? 1 : 0
  name                        = "oceanbase-to-control"
  resource_group_name         = local.oceanbase_rg_name
  virtual_network_name        = local.oceanbase_vnet_name
  remote_virtual_network_id   = "/subscriptions/${var.ARM_SUBSCRIPTION_ID}/resourceGroups/${var.control_resource_group_name}/providers/Microsoft.Network/virtualNetworks/${var.control_vnet_name}"
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}
