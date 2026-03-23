############### RG #################
data azurerm_subscription "current" { }
data "azurerm_client_config" "current" {}

# Create RG only if NOT using existing networks; otherwise data-source the existing RG
resource "azurerm_resource_group" "example" {
  count    = var.use_existing_control_network ? 0 : 1
  location = var.resource_group_location
  name     = var.resource_group_name
}

data "azurerm_resource_group" "example" {
  count = var.use_existing_control_network ? 1 : 0
  name  = var.resource_group_name
}

locals {
  resource_group_name  = var.use_existing_control_network ? data.azurerm_resource_group.example[0].name : azurerm_resource_group.example[0].name
  resource_group_id    = var.use_existing_control_network ? data.azurerm_resource_group.example[0].id : azurerm_resource_group.example[0].id
  resource_group_location = var.use_existing_control_network ? data.azurerm_resource_group.example[0].location : azurerm_resource_group.example[0].location
}

resource "azurerm_virtual_network" "control" {
  count               = var.use_existing_control_network ? 0 : 1
  name                = var.control_vnet_name
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  address_space       = ["172.17.0.0/16"]
}

data "azurerm_virtual_network" "control" {
  count               = var.use_existing_control_network ? 1 : 0
  name                = var.control_vnet_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "control" {
  count                        = var.use_existing_control_network ? 0 : 1
  name                         = var.control_subnet_name
  resource_group_name          = local.resource_group_name
  virtual_network_name         = azurerm_virtual_network.control[0].name
  address_prefixes             = ["172.17.1.0/24"]
  default_outbound_access_enabled = false
}

data "azurerm_subnet" "control" {
  count                = var.use_existing_control_network ? 1 : 0
  name                 = var.control_subnet_name
  virtual_network_name = var.control_vnet_name
  resource_group_name  = var.resource_group_name
}

locals {
  control_subnet_id = var.use_existing_control_network ? data.azurerm_subnet.control[0].id : azurerm_subnet.control[0].id
  control_nsg_id    = var.control_nsg_id != "" ? var.control_nsg_id : (var.use_existing_control_network ? null : azurerm_network_security_group.example[0].id)
  control_existing_nsg_rg_name = var.control_nsg_id != "" ? split("/", var.control_nsg_id)[4] : null
  control_existing_nsg_name    = var.control_nsg_id != "" ? split("/", var.control_nsg_id)[8] : null
  attach_control_nsg = var.control_nsg_id != "" || !var.use_existing_control_network
}

resource "azurerm_network_security_group" "example" {
  count               = var.control_nsg_id != "" || var.use_existing_control_network ? 0 : 1
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
  count                     = !var.use_existing_control_network && local.attach_control_nsg ? 1 : 0
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

resource "azurerm_public_ip" "control" {
  name                = "control-ip"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"

  lifecycle {
    ignore_changes = [ip_tags, tags, zones]
  }
}

resource "azurerm_network_interface" "example" {
  name                = "control-nic"
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.control_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.control.id
  }
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
  # provisioner "remote-exec" {
  #   when    = destroy
  #   inline = [
  #     "cd ecom-middleware-ops/terraform/kafka",
  #     "terraform destroy -var-file='sub_id.tfvars' -auto-approve",
  #   ]
  # }
}


resource "azurerm_role_assignment" "control" {
  scope              = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id       = azurerm_linux_virtual_machine.example.identity[0].principal_id
}



