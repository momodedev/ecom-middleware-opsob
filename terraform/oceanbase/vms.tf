###################### OceanBase Observer VMs #####################

# Create network interfaces for each OceanBase observer
resource "azurerm_network_interface" "oceanbase_observers" {
  count               = var.oceanbase_instance_count
  name                = "ob-nic-${count.index}"
  location            = local.oceanbase_rg_location
  resource_group_name = local.oceanbase_rg_name

  ip_configuration {
    name                          = "ob-ip-config-${count.index}"
    subnet_id                     = local.oceanbase_subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = {
    Environment = "production"
    Component   = "oceanbase-observer"
    Index       = count.index
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# Associate NSG with each network interface
resource "azurerm_network_interface_security_group_association" "oceanbase_observers" {
  count                     = local.attach_oceanbase_nsg ? var.oceanbase_instance_count : 0
  network_interface_id      = azurerm_network_interface.oceanbase_observers[count.index].id
  network_security_group_id = local.oceanbase_nsg_id
}

# Create individual OceanBase observer VMs
resource "azurerm_linux_virtual_machine" "oceanbase_observers" {
  count               = var.oceanbase_instance_count
  name                = "ob-observer-${count.index}"
  location            = local.oceanbase_rg_location
  resource_group_name = local.oceanbase_rg_name
  size                = var.oceanbase_vm_size
  zone                = var.enable_availability_zones && var.oceanbase_vm_zone != "" ? var.oceanbase_vm_zone : null

  network_interface_ids = [
    azurerm_network_interface.oceanbase_observers[count.index].id
  ]

  # Add delay between VM creations to avoid Azure throttling
  provisioner "local-exec" {
    command = "sleep ${count.index * 30}"
  }

  # Extended timeouts for large VMs
  timeouts {
    create = "45m"
    update = "30m"
    delete = "30m"
  }

  computer_name  = "ob-observer-${count.index}"
  admin_username = "oceanadmin"

  admin_ssh_key {
    username   = "oceanadmin"
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = var.rocky_image_publisher
    offer     = var.rocky_image_offer
    sku       = var.rocky_image_sku
    version   = var.rocky_image_version
  }

  plan {
    publisher = var.rocky_image_publisher
    product   = var.rocky_image_offer
    name      = var.rocky_image_sku
  }

  # Bootstrap with cloud-init for system dependencies and disk mounting
  custom_data = base64encode(templatefile("${path.module}/cloud-init.tpl", {
    oceanbase_admin_username = "oceanadmin"
    oceanbase_data_disk_size_gb = var.oceanbase_data_disk_size_gb
    oceanbase_redo_disk_size_gb = var.oceanbase_redo_disk_size_gb
    rocky_target_release = var.rocky_target_release
  }))

  tags = {
    Environment = "production"
    Component   = "oceanbase-observer"
    Index       = count.index
    Zone        = var.enable_availability_zones && var.oceanbase_vm_zone != "" ? var.oceanbase_vm_zone : "none"
  }

  lifecycle {
    ignore_changes = [
      bypass_platform_safety_checks_on_user_schedule_enabled,
      tags
    ]
  }
}

# Data disks for OceanBase data storage
resource "azurerm_managed_disk" "oceanbase_data" {
  count                = var.oceanbase_instance_count
  name                 = "ob-data-disk-${count.index}"
  location             = local.oceanbase_rg_location
  resource_group_name  = local.oceanbase_rg_name
  storage_account_type = "PremiumV2_LRS"  # Premium SSD v2 LRS for better performance
  create_option        = "Empty"
  disk_size_gb         = var.oceanbase_data_disk_size_gb

  zone = var.enable_availability_zones && var.oceanbase_vm_zone != "" ? var.oceanbase_vm_zone : null

  tags = {
    Environment = "production"
    Component   = "oceanbase-data-disk"
    Index       = count.index
  }

  lifecycle {
    # Existing disks were created as Premium_LRS; Azure rejects in-place SKU upgrade on attached disks.
    # New disks created by this module will use PremiumV2_LRS as specified above.
    ignore_changes = [storage_account_type]
  }
}

# Attach data disks to observer VMs
resource "azurerm_virtual_machine_data_disk_attachment" "oceanbase_data" {
  count              = var.oceanbase_instance_count
  managed_disk_id    = azurerm_managed_disk.oceanbase_data[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.oceanbase_observers[count.index].id
  lun                = "10"
  # Premium SSD v2 (PremiumV2_LRS) only supports None caching.
  caching            = "None"
}

# Redo log disks for OceanBase
resource "azurerm_managed_disk" "oceanbase_redo" {
  count                = var.oceanbase_instance_count
  name                 = "ob-redo-disk-${count.index}"
  location             = local.oceanbase_rg_location
  resource_group_name  = local.oceanbase_rg_name
  storage_account_type = "PremiumV2_LRS"  # Premium SSD v2 LRS for better performance
  create_option        = "Empty"
  disk_size_gb         = var.oceanbase_redo_disk_size_gb

  zone = var.enable_availability_zones && var.oceanbase_vm_zone != "" ? var.oceanbase_vm_zone : null

  tags = {
    Environment = "production"
    Component   = "oceanbase-redo-disk"
    Index       = count.index
  }

  lifecycle {
    ignore_changes = [storage_account_type]
  }
}

# Attach redo disks to observer VMs
resource "azurerm_virtual_machine_data_disk_attachment" "oceanbase_redo" {
  count              = var.oceanbase_instance_count
  managed_disk_id    = azurerm_managed_disk.oceanbase_redo[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.oceanbase_observers[count.index].id
  lun                = "11"
  # Premium SSD v2 (PremiumV2_LRS) only supports None caching.
  caching            = "None"
}
