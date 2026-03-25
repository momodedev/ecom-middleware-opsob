############### RG #################
data azurerm_subscription "current" { }
data "azurerm_client_config" "current" {}

# Create RG (will succeed if it already exists - Azure is idempotent)
resource "azurerm_resource_group" "example" {
  location = var.resource_group_location
  name     = var.resource_group_name
  
  lifecycle {
    ignore_changes = [tags, location]
  }
}

locals {
  resource_group_name  = azurerm_resource_group.example.name
  resource_group_id    = azurerm_resource_group.example.id
  resource_group_location = azurerm_resource_group.example.location
}

# Create VNet if it doesn't exist (Azure will return existing VNet)
resource "azurerm_virtual_network" "control" {
  name                = var.control_vnet_name
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  address_space       = ["172.17.0.0/16"]
  
  lifecycle {
    ignore_changes = [address_space, tags]
  }
}

locals {
  control_vnet_name = azurerm_virtual_network.control.name
  control_vnet_id   = azurerm_virtual_network.control.id
}

# Create subnet if it doesn't exist (Azure will return existing subnet)
resource "azurerm_subnet" "control" {
  name                         = var.control_subnet_name
  resource_group_name          = local.resource_group_name
  virtual_network_name         = local.control_vnet_name
  address_prefixes             = ["172.17.1.0/24"]
  default_outbound_access_enabled = false
  
  lifecycle {
    ignore_changes = [address_prefixes]
  }
}

locals {
  control_subnet_id = azurerm_subnet.control.id
}

# Check if NSG exists - use provided ID or create new one
locals {
  control_nsg_id    = var.control_nsg_id != "" ? var.control_nsg_id : azurerm_network_security_group.example[0].id
  control_existing_nsg_rg_name = var.control_nsg_id != "" ? split("/", var.control_nsg_id)[4] : local.resource_group_name
  control_existing_nsg_name    = var.control_nsg_id != "" ? split("/", var.control_nsg_id)[8] : azurerm_network_security_group.example[0].name
  attach_control_nsg = var.control_nsg_id != "" || true  # Always attach NSG
}

resource "azurerm_network_security_group" "example" {
  count               = var.control_nsg_id != "" ? 0 : 1
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
  count                     = local.attach_control_nsg ? 1 : 0
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

# Create public IP (Azure will return existing if it matches)
resource "azurerm_public_ip" "control" {
  name                = "control-ip"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"

  lifecycle {
    ignore_changes = [ip_tags, tags, zones]
  }
}

locals {
  control_public_ip_id = azurerm_public_ip.control.id
}

# Create NIC (Azure will return existing if it matches)
resource "azurerm_network_interface" "example" {
  name                = "control-nic"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.control.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.control.id
  }
  
  lifecycle {
    ignore_changes = [ip_configuration, tags]
  }
}

locals {
  control_nic_id = azurerm_network_interface.example.id
}

resource "azurerm_linux_virtual_machine" "example" {
  name                = "control-node"
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  size                = var.control_vm_size
  network_interface_ids = [
    azurerm_network_interface.example.id,
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
    version   = "latest"
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
      bypass_platform_safety_checks_on_user_schedule_enabled
    ]
  }
}

locals {
  control_vm_id = azurerm_linux_virtual_machine.example.id
  control_vm_principal_id = try(azurerm_linux_virtual_machine.example.identity[0].principal_id, "")
}

# Role assignment will always be created if VM is created
# We can't check for existing role assignments with azurerm provider
# So we'll use try() to handle cases where it might not exist yet
resource "azurerm_role_assignment" "control" {
  scope                = local.resource_group_id
  role_definition_name = "Contributor"
  principal_id         = local.control_vm_principal_id
}
