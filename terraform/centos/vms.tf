# ============================================================
# CentOS 7.9 + Azure V5  –  Kafka 2.3.1 broker VMs
#
# NOTE: Apply this module FROM the control node (Rocky Linux).
#       The null_resource local-exec provisioner needs the
#       Ansible venv and the cloned repository on the same host.
# ============================================================

locals {
  computed_ansible_venv_path = (
    var.ansible_venv_path != ""
    ? var.ansible_venv_path
    : "/home/${var.control_node_user}/ansible-venv"
  )
  computed_repository_base = (
    var.repository_base_dir != ""
    ? var.repository_base_dir
    : "/home/${var.control_node_user}/${var.repository_name}"
  )
  ansible_working_dir = "${local.computed_repository_base}/ansible_centos"

  # Ansible-reachable IPs:
  #   is_public=true  → public IPs  (new VNet not peered to control node VNet)
  #   is_public=false → private IPs (assumes VNet peering / shared subnet)
  ansible_host_ips = [for idx in range(var.kafka_instance_count) :
    length(azurerm_public_ip.brokers) > idx
    ? azurerm_public_ip.brokers[idx].ip_address
    : azurerm_linux_virtual_machine.brokers[idx].private_ip_address
  ]

}

# ── Optional public IPs (required when new VNet is not peered to control VNet) ──——

resource "azurerm_public_ip" "brokers" {
  count               = var.is_public ? var.kafka_instance_count : 0
  name                = "kafka-centos-pip-${count.index}"
  location            = local.foundation_rg_location
  resource_group_name = local.foundation_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"

  lifecycle {
    ignore_changes = [ip_tags, tags]
  }
}

# ── Network interfaces ───────────────────────────────────────────────────────

resource "azurerm_network_interface" "brokers" {
  count               = var.kafka_instance_count
  name                = "kafka-centos-nic-${count.index}"
  location            = local.foundation_rg_location
  resource_group_name = local.foundation_rg_name

  ip_configuration {
    name                          = "kafka-centos-ipconfig"
    subnet_id                     = local.foundation_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.is_public ? azurerm_public_ip.brokers[count.index].id : null
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

resource "azurerm_network_interface_security_group_association" "brokers" {
  count                     = var.kafka_instance_count
  network_interface_id      = azurerm_network_interface.brokers[count.index].id
  network_security_group_id = local.foundation_nsg_id
}

# ── CentOS 7.9 Kafka broker VMs ─────────────────────────────────────────────

resource "azurerm_linux_virtual_machine" "brokers" {
  count               = var.kafka_instance_count
  name                = "kafka-broker-${count.index}"
  location            = local.foundation_rg_location
  resource_group_name = local.foundation_rg_name
  size                = var.kafka_vm_size
  zone                = var.enable_availability_zones && var.kafka_vm_zone != "" ? var.kafka_vm_zone : null

  network_interface_ids = [azurerm_network_interface.brokers[count.index].id]

  computer_name  = "kafka-broker-${count.index}"
  admin_username = var.kafka_admin_username

  admin_ssh_key {
    username   = var.kafka_admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  # CentOS 7.9 from OpenLogic – no marketplace plan block required
  source_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7_9"
    version   = "latest"
  }

  # CentOS 7.9 yum-based bootstrap (installs Java 11, Python 3, formats data disk)
  custom_data = base64encode(templatefile("${path.module}/cloud-init.tpl", {
    kafka_admin_username = var.kafka_admin_username
  }))

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {
    storage_account_uri = null
  }

  timeouts {
    create = "45m"
    update = "30m"
    delete = "30m"
  }

  lifecycle {
    ignore_changes = [
      bypass_platform_safety_checks_on_user_schedule_enabled,
      custom_data,
      tags,
    ]
  }

  depends_on = [
    azurerm_network_interface.brokers,
    azurerm_network_interface_security_group_association.brokers,
  ]
}

# ── Premium SSD data disk – caching=None for Kafka log storage ───────────────

resource "azurerm_managed_disk" "data_disk" {
  count                = var.kafka_instance_count
  # Azure does not allow in-place migration from Premium_LRS to PremiumV2_LRS.
  # Encode disk family in the name so Terraform performs create+replace cleanly.
  name                 = var.use_premium_v2_disks ? "kafka-centos-data-v2-${count.index}" : "kafka-centos-data-${count.index}"
  location             = local.foundation_rg_location
  resource_group_name  = local.foundation_rg_name
  storage_account_type = var.use_premium_v2_disks ? "PremiumV2_LRS" : "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.kafka_data_disk_size_gb
  zone                 = (var.use_premium_v2_disks && var.enable_availability_zones && var.kafka_vm_zone != "") ? var.kafka_vm_zone : null

  # Premium SSD v2 performance knobs (ignored when Premium_LRS is used)
  disk_iops_read_write = var.use_premium_v2_disks ? var.kafka_data_disk_iops : null
  disk_mbps_read_write = var.use_premium_v2_disks ? var.kafka_data_disk_throughput_mbps : null

  tags = {
    Environment = "production"
    Component   = "kafka"
    Index       = count.index
    DiskType    = var.use_premium_v2_disks ? "PremiumV2" : "Premium"
  }

  lifecycle {
    ignore_changes = [
      tags,
      zone
    ]

    precondition {
      condition     = !var.use_premium_v2_disks || (var.enable_availability_zones && var.kafka_vm_zone != "")
      error_message = "Premium SSD v2 can only be attached to zonal VMs. Set enable_availability_zones=true and kafka_vm_zone to 1, 2, or 3."
    }
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "data_disk" {
  count              = var.kafka_instance_count
  managed_disk_id    = azurerm_managed_disk.data_disk[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.brokers[count.index].id
  lun                = 0
  caching            = "None"
}

# ── Ansible provisioner – deploy Kafka 2.3.1 + monitoring on CentOS brokers ─
# IMPORTANT: terraform apply must be run FROM the control node so that
#            local.ansible_working_dir and the Ansible venv exist.

resource "null_resource" "ansible" {
  count = var.enable_ansible_provisioner ? 1 : 0

  triggers = {
    instance_count = var.kafka_instance_count
    broker_ips     = join(",", sort(azurerm_linux_virtual_machine.brokers[*].private_ip_address))
    ansible_run_id = var.ansible_run_id
  }

  provisioner "local-exec" {
    working_dir = local.ansible_working_dir
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      source ${local.computed_ansible_venv_path}/bin/activate

      az login --identity >/dev/null 2>&1 || { echo "ERROR: Azure MSI login failed"; exit 1; }

      echo "[centos-lane] Waiting 240s for CentOS 7.9 VMs to complete cloud-init..."
      sleep 240

      # Hardened CentOS lane deployment from dedicated ansible_centos workspace
      bash scripts/deploy_centos_cluster.sh ${local.foundation_rg_name} ${var.kafka_admin_username} ${var.control_node_user}

      echo "[centos-lane] ✓ CentOS 7.9 / V5 Kafka deployment complete."
    EOT
  }

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.data_disk,
    azurerm_linux_virtual_machine.brokers,
  ]
}
