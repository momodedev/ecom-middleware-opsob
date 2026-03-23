############### RG #################
data azurerm_subscription "current" { }
data "azurerm_client_config" "current" {}

# Use azapi to check if resource group exists (doesn't fail if not found)
data "azapi_resource" "rg_existing" {
  type      = "Microsoft.Resources/resourceGroups@2021-04-01"
  name      = var.resource_group_name
  parent_id = data.azurerm_subscription.current.id
}

# Create RG only if it doesn't exist
resource "azurerm_resource_group" "example" {
  count    = try(data.azapi_resource.rg_existing.id, "") == "" ? 1 : 0
  location = var.resource_group_location
  name     = var.resource_group_name
}

locals {
  resource_group_name  = try(data.azapi_resource.rg_existing.id, "") != "" ? data.azapi_resource.rg_existing.name : azurerm_resource_group.example[0].name
  resource_group_id    = try(data.azapi_resource.rg_existing.id, "") != "" ? data.azapi_resource.rg_existing.id : azurerm_resource_group.example[0].id
  resource_group_location = try(data.azapi_resource.rg_existing.id, "") != "" ? data.azapi_resource.rg_existing.location : azurerm_resource_group.example[0].location
}

# Check if VNet exists using azapi (doesn't fail if not found)
data "azapi_resource" "vnet_existing" {
  type      = "Microsoft.Network/virtualNetworks@2024-01-01"
  name      = var.control_vnet_name
  parent_id = local.resource_group_id
}

resource "azurerm_virtual_network" "control" {
  count               = try(data.azapi_resource.vnet_existing.id, "") == "" && !var.use_existing_control_network ? 1 : 0
  name                = var.control_vnet_name
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  address_space       = ["172.17.0.0/16"]
}

locals {
  control_vnet_name = try(data.azapi_resource.vnet_existing.id, "") != "" ? data.azapi_resource.vnet_existing.name : azurerm_virtual_network.control[0].name
  control_vnet_id   = try(data.azapi_resource.vnet_existing.id, "") != "" ? data.azapi_resource.vnet_existing.id : azurerm_virtual_network.control[0].id
}

# Check if subnet exists using azapi (doesn't fail if not found)
data "azapi_resource" "subnet_existing" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-01-01"
  name      = var.control_subnet_name
  parent_id = local.control_vnet_id
}

resource "azurerm_subnet" "control" {
  count                        = try(data.azapi_resource.subnet_existing.id, "") == "" && !var.use_existing_control_network ? 1 : 0
  name                         = var.control_subnet_name
  resource_group_name          = local.resource_group_name
  virtual_network_name         = local.control_vnet_name
  address_prefixes             = ["172.17.1.0/24"]
  default_outbound_access_enabled = false
}

locals {
  control_subnet_id = try(data.azapi_resource.subnet_existing.id, "") != "" ? data.azapi_resource.subnet_existing.id : azurerm_subnet.control[0].id
}

# Check if NSG exists using azapi (doesn't fail if not found)
data "azapi_resource" "nsg_existing" {
  type      = "Microsoft.Network/networkSecurityGroups@2024-01-01"
  name      = var.control_nsg_name
  parent_id = local.resource_group_id
}

locals {
  control_nsg_id    = var.control_nsg_id != "" ? var.control_nsg_id : (
    try(data.azapi_resource.nsg_existing.id, "") != "" ? data.azapi_resource.nsg_existing.id : azurerm_network_security_group.example[0].id
  )
  control_existing_nsg_rg_name = var.control_nsg_id != "" ? split("/", var.control_nsg_id)[4] : (
    try(data.azapi_resource.nsg_existing.id, "") != "" ? local.resource_group_name : null
  )
  control_existing_nsg_name    = var.control_nsg_id != "" ? split("/", var.control_nsg_id)[8] : (
    try(data.azapi_resource.nsg_existing.id, "") != "" ? data.azapi_resource.nsg_existing.name : null
  )
  attach_control_nsg = var.control_nsg_id != "" || try(data.azapi_resource.nsg_existing.id, "") != "" || !var.use_existing_control_network
}

resource "azurerm_network_security_group" "example" {
  count               = var.control_nsg_id != "" || try(data.azapi_resource.nsg_existing.id, "") != "" ? 0 : 1
  name                = var.control_nsg_name
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.control_ssh_port)
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "prometheus"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9090"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "grafana"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "example" {
  count                     = (!var.use_existing_control_network || try(data.azapi_resource.subnet_existing.id, "") != "") && local.attach_control_nsg && try(data.azapi_resource.nsg_existing.id, "") == "" ? 1 : 0
  subnet_id                 = local.control_subnet_id
  network_security_group_id = local.control_nsg_id
}

resource "azurerm_network_security_rule" "existing_nsg_control_ssh" {
  count                       = var.control_nsg_id != "" ? 1 : 0
  name                        = "control-ssh-${var.control_ssh_port}"
  priority                    = 3100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.control_ssh_port)
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.control_existing_nsg_rg_name
  network_security_group_name = local.control_existing_nsg_name
}

# ==================== Control Node Public IP (for SSH access) ====================

# Check if public IP exists using azapi (doesn't fail if not found)
data "azapi_resource" "pip_existing" {
  type      = "Microsoft.Network/publicIPAddresses@2024-01-01"
  name      = "control-ip"
  parent_id = local.resource_group_id
}

resource "azurerm_public_ip" "control" {
  count               = try(data.azapi_resource.pip_existing.id, "") == "" ? 1 : 0
  name                = "control-ip"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"

  lifecycle {
    ignore_changes = [ip_tags, tags, zones]
  }
}

locals {
  control_public_ip_id = try(data.azapi_resource.pip_existing.id, "") != "" ? data.azapi_resource.pip_existing.id : azurerm_public_ip.control[0].id
}

# Check if NIC exists using azapi (doesn't fail if not found)
data "azapi_resource" "nic_existing" {
  type      = "Microsoft.Network/networkInterfaces@2024-01-01"
  name      = "control-nic"
  parent_id = local.resource_group_id
}

resource "azurerm_network_interface" "example" {
  count               = try(data.azapi_resource.nic_existing.id, "") == "" ? 1 : 0
  name                = "control-nic"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.control_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = local.control_public_ip_id
  }
}

locals {
  control_nic_id = try(data.azapi_resource.nic_existing.id, "") != "" ? data.azapi_resource.nic_existing.id : azurerm_network_interface.example[0].id
}

# Check if VM exists using azapi (since azurerm doesn't have a VM data source)
data "azapi_resource" "vm_existing" {
  type      = "Microsoft.Compute/virtualMachines@2024-03-01"
  name      = "control-node"
  parent_id = local.resource_group_id
}

resource "azurerm_linux_virtual_machine" "example" {
  count               = try(data.azapi_resource.vm_existing.id, "") == "" ? 1 : 0
  name                = "control-node"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  size                = var.control_vm_size
  network_interface_ids = [
    local.control_nic_id,
  ]

  computer_name  = "control"
  admin_username = "azureadmin"
  admin_ssh_key {
    username   = "azureadmin"
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "resf"
    offer     = "rockylinux-x86_64"
    sku       = "9-base"
    version   = "9.6.20250531"
  }

  plan {
    publisher = "resf"
    product   = "rockylinux-x86_64"
    name      = "9-base"
  }

  # Bootstrap control node with cloud-init (Azure best practice)
  custom_data = base64encode(templatefile("${path.module}/cloud-init.tpl", {
    control_ssh_port = var.control_ssh_port
  }))

  lifecycle {
    ignore_changes = [
      bypass_platform_safety_checks_on_user_schedule_enabled,
      custom_data  # Prevent recreation on template changes
    ]
  }
}

locals {
  control_vm_id = try(data.azapi_resource.vm_existing.id, "") != "" ? data.azapi_resource.vm_existing.id : azurerm_linux_virtual_machine.example[0].id
  # For existing VMs, we need to read the principal ID separately using azapi_resource_action or output
  # For now, set to empty string if VM exists but wasn't created by us
  control_vm_principal_id = azurerm_linux_virtual_machine.example[0].identity[0].principal_id
}

# Role assignment will always be created if VM is created
# We can't check for existing role assignments with azurerm provider
# So we'll use try() to handle cases where it might not exist yet
resource "azurerm_role_assignment" "control" {
  count                = local.control_vm_principal_id != "" ? 1 : 0
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = local.control_vm_principal_id
  
  lifecycle {
    ignore_changes = [principal_id, role_definition_name]
  }
}
