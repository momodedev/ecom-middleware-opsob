# --------------------------------------------------------------------------- #
# OceanBase Standalone VM  (Standard_D16s_v6 · Rocky Linux 9 · 16 vCPU / 64 GiB)
# --------------------------------------------------------------------------- #
resource "azurerm_linux_virtual_machine" "ob_standalone" {
  name                = var.vm_name
  resource_group_name = local.rg_name
  location            = local.rg_location
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  # Rocky Linux 9 image available in westus.
  # Note: westus currently exposes Rocky as resf:rockylinux-x86_64:9-base.
  source_image_reference {
    publisher = "resf"
    offer     = "rockylinux-x86_64"
    sku       = "9-base"
    version   = "latest"
  }

  # Marketplace plan required by the Rocky image.
  plan {
    publisher = "resf"
    product   = "rockylinux-x86_64"
    name      = "9-base"
  }

  os_disk {
    name                 = "${var.vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  # Inject OS-level preparation via cloud-init
  custom_data = base64encode(templatefile("${path.module}/cloud-init.tpl", {
    ob_admin_username = var.ob_admin_username
  }))

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {
    storage_account_uri = null
  }

  tags = {
    Environment = "standalone"
    Component   = "oceanbase"
  }

  lifecycle {
    ignore_changes = [
      bypass_platform_safety_checks_on_user_schedule_enabled,
      custom_data,
      tags,
    ]
  }

  # Extended timeout – D16s_v6 provisioning can take up to 15 minutes
  timeouts {
    create = "30m"
    update = "20m"
    delete = "20m"
  }
}

# --------------------------------------------------------------------------- #
# Data disk  (/oceanbase/data)
# --------------------------------------------------------------------------- #
resource "azurerm_managed_disk" "data" {
  name                 = "${var.vm_name}-data"
  location             = local.rg_location
  resource_group_name  = local.rg_name
  storage_account_type = "PremiumV2_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb

  tags = { Component = "ob-standalone-data" }
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_linux_virtual_machine.ob_standalone.id
  lun                = "10"
  caching            = "None"
}

# --------------------------------------------------------------------------- #
# Redo-log disk  (/oceanbase/redo)
# --------------------------------------------------------------------------- #
resource "azurerm_managed_disk" "redo" {
  name                 = "${var.vm_name}-redo"
  location             = local.rg_location
  resource_group_name  = local.rg_name
  storage_account_type = "PremiumV2_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.redo_disk_size_gb

  tags = { Component = "ob-standalone-redo" }
}

resource "azurerm_virtual_machine_data_disk_attachment" "redo" {
  managed_disk_id    = azurerm_managed_disk.redo.id
  virtual_machine_id = azurerm_linux_virtual_machine.ob_standalone.id
  lun                = "11"
  caching            = "None"

  # Attach redo after data to avoid LUN conflicts
  depends_on = [azurerm_virtual_machine_data_disk_attachment.data]
}
