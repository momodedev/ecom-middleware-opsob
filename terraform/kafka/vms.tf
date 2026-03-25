###################### Kafka Broker VMs #####################
# This file defines individual virtual machines for Kafka brokers
# (renamed from vmss.tf - now using VMs instead of VMSS for better control)

# Optional public IPs for brokers when is_public=true
resource "azurerm_public_ip" "kafka_brokers" {
  count               = var.is_public ? var.kafka_instance_count : 0
  name                = "kafka-pip-${count.index}"
  location            = local.kafka_rg_location
  resource_group_name = local.kafka_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment = "production"
    Component   = "kafka-broker"
    Index       = count.index
    Purpose     = "public-access"
  }

  lifecycle {
    ignore_changes = [
      tags,
      # Azure can inject ip_tags metadata (for example FirstPartyUsage), which can
      # otherwise trigger unnecessary ForceNew replacement for Public IP resources.
      ip_tags
    ]
    # Prevent accidental deletion of public IPs
    prevent_destroy = false
  }
}

# Create network interfaces for each Kafka broker (public IP optional)
resource "azurerm_network_interface" "kafka_brokers" {
  count               = var.kafka_instance_count
  name                = "kafka-nic-${count.index}"
  location            = local.kafka_rg_location
  resource_group_name = local.kafka_rg_name

  ip_configuration {
    name                          = "kafka-ip-config-${count.index}"
    subnet_id                     = local.kafka_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.is_public ? azurerm_public_ip.kafka_brokers[count.index].id : null
  }

  tags = {
    Environment = "production"
    Component   = "kafka-broker"
    Index       = count.index
    PublicIP    = var.is_public ? "public" : "none"
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Associate NSG with each network interface
resource "azurerm_network_interface_security_group_association" "kafka_brokers" {
  count                     = local.attach_kafka_nsg ? var.kafka_instance_count : 0
  network_interface_id      = azurerm_network_interface.kafka_brokers[count.index].id
  network_security_group_id = local.kafka_nsg_id
}

# Create individual Kafka broker VMs
# Note: Using individual VMs instead of VMSS for granular control and easier management
resource "azurerm_linux_virtual_machine" "kafka_brokers" {
  count               = var.kafka_instance_count
  name                = "kafka-broker-${count.index}"
  location            = local.kafka_rg_location
  resource_group_name = local.kafka_rg_name
  size                = var.kafka_vm_size
  zone                = var.enable_availability_zones && var.kafka_vm_zone != "" ? var.kafka_vm_zone : null

  network_interface_ids = [
    azurerm_network_interface.kafka_brokers[count.index].id
  ]

  # Add delay between VM creations to avoid Azure throttling
  provisioner "local-exec" {
    command = "sleep ${count.index * 30}"
  }

  # Extended timeouts for large VMs and slower regions
  timeouts {
    create = "45m"
    update = "30m"
    delete = "30m"
  }

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

  # Bootstrap with cloud-init for system dependencies
  custom_data = base64encode(templatefile("${path.module}/cloud-init.tpl", {
    kafka_admin_username = var.kafka_admin_username
  }))

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {
    storage_account_uri = null
  }

  tags = {
    Environment = "production"
    Component   = "kafka"
    Index       = count.index
    BrokerID    = count.index
  }

  lifecycle {
    ignore_changes = [
      bypass_platform_safety_checks_on_user_schedule_enabled,
      custom_data,
      tags
    ]
    # Prevent accidental deletion of brokers
    prevent_destroy = false
  }

  # Ensure NICs are ready before VM creation
  depends_on = [
    azurerm_network_interface.kafka_brokers,
    azurerm_network_interface_security_group_association.kafka_brokers
  ]
}

# Data Disks - PremiumV2_LRS (zone-required, custom IOPS) or Premium_LRS (tier-based)
resource "azurerm_managed_disk" "kafka_data_disk" {
  count               = var.kafka_instance_count
  name                = "kafka-data-disk-${count.index}"
  location            = local.kafka_rg_location
  resource_group_name = local.kafka_rg_name

  storage_account_type = var.use_premium_v2_disks ? "PremiumV2_LRS" : "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.kafka_data_disk_size_gb
  
  # Zone required for PremiumV2_LRS; optional for Premium_LRS
  zone = (var.use_premium_v2_disks && var.enable_availability_zones && var.kafka_vm_zone != "") ? var.kafka_vm_zone : null

  # PremiumV2 custom performance (ignored for Premium_LRS)
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
      # Prevent Terraform from recreating disks due to zone attribute changes
      # Zone may be set to null in some scenarios but should not trigger replacement
      zone
    ]
    # WARNING: Prevent accidental disk deletion (data loss!)
    prevent_destroy = false
  }
}

# Attach data disks to each VM
resource "azurerm_virtual_machine_data_disk_attachment" "kafka_data_disk" {
  count              = var.kafka_instance_count
  managed_disk_id    = azurerm_managed_disk.kafka_data_disk[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.kafka_brokers[count.index].id
  lun                = 0
  caching            = "None"
}

# Output private IPs only (no public IPs for private cluster)
output "kafka_private_ips" {
  description = "Private IP addresses assigned to Kafka brokers."
  value       = azurerm_linux_virtual_machine.kafka_brokers[*].private_ip_address
}

# Output public IPs when is_public=true
output "kafka_public_ips" {
  description = "Public IP addresses assigned to Kafka brokers (only when is_public=true)."
  value       = var.is_public ? azurerm_public_ip.kafka_brokers[*].ip_address : []
}

# Launch Ansible playbook after all VMs are ready
# Triggers on VM count, IP list, or ansible_run_id changes
resource "null_resource" "launch_ansible_playbook" {
  triggers = {
    kafka_count    = var.kafka_instance_count
    private_ips    = join(",", sort(azurerm_linux_virtual_machine.kafka_brokers[*].private_ip_address))
    ansible_run_id = var.ansible_run_id
  }

  provisioner "local-exec" {
    working_dir = local.ansible_working_dir
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      source ${local.computed_ansible_venv_path}/bin/activate

      # FIX: Define the correct prefix to match your VM names in vms.tf
      export KAFKA_VM_PREFIX="kafka"
      
      # Login to Azure
      az login --identity >/dev/null 2>&1 || { echo "Azure login failed"; exit 1; }
      
      # Wait for VMs to complete cloud-init bootstrap
      echo "Waiting 120 seconds for VMs to complete cloud-init bootstrap..."
      sleep 120
      
      # Validate VMs are ready
      echo "Validating VM readiness..."
      bash ${local.computed_repository_base}/ansible/scripts/validate_vms_ready.sh ${local.kafka_rg_name} ${var.kafka_admin_username} || {
        echo "ERROR: VMs are not ready. Waiting additional 60 seconds..."
        sleep 60
        bash ${local.computed_repository_base}/ansible/scripts/validate_vms_ready.sh ${local.kafka_rg_name} ${var.kafka_admin_username}
      }
      
      # Generate inventory
      mkdir -p inventory
      bash ${local.computed_repository_base}/ansible/scripts/inventory_script_hosts_vms.sh ${local.kafka_rg_name} ${var.kafka_admin_username} > inventory/kafka_hosts
      
      # Verify inventory was generated
      if [ ! -s inventory/kafka_hosts ]; then
        echo "ERROR: Inventory file is empty"
        exit 1
      fi
      
      echo "Generated inventory:"
      cat inventory/kafka_hosts
      
      # Deploy Kafka with retry on failure
      echo "Deploying Kafka brokers..."
      ansible-playbook -i inventory/kafka_hosts playbooks/deploy_kafka_playbook.yaml || {
        echo "First attempt failed, retrying after 30s..."
        sleep 30
        ansible-playbook -i inventory/kafka_hosts playbooks/deploy_kafka_playbook.yaml
      }
      
      # Deploy monitoring
      echo "Deploying monitoring stack..."
      ansible-playbook -i inventory/inventory.ini playbooks/deploy_monitoring_playbook.yml
    EOT
  }

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.kafka_data_disk,
    azurerm_linux_virtual_machine.kafka_brokers
  ]
}
