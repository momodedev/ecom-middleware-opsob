output "resource_group_name" {
  description = "Selected existing resource group name."
  value       = local.foundation_rg_name
}

output "vnet_name" {
  description = "Selected existing virtual network name."
  value       = local.foundation_vnet_name
}

output "subnet_id" {
  description = "Selected existing subnet ID."
  value       = local.foundation_subnet_id
}

output "nsg_id" {
  description = "Selected existing NSG ID."
  value       = local.foundation_nsg_id
}

output "kafka_broker_public_ips" {
  description = "Public IP addresses of CentOS Kafka brokers (populated when is_public=true)."
  value       = var.is_public ? azurerm_public_ip.brokers[*].ip_address : []
}

output "kafka_broker_private_ips" {
  description = "Private IP addresses of CentOS Kafka brokers."
  value       = azurerm_linux_virtual_machine.brokers[*].private_ip_address
}

output "kafka_data_disk_sku" {
  description = "Configured data disk SKU for CentOS brokers."
  value       = var.use_premium_v2_disks ? "PremiumV2_LRS" : "Premium_LRS"
}

output "kafka_data_disk_performance" {
  description = "Configured data disk performance settings for CentOS brokers."
  value = {
    size_gib       = var.kafka_data_disk_size_gb
    iops           = var.use_premium_v2_disks ? var.kafka_data_disk_iops : null
    throughput_mbs = var.use_premium_v2_disks ? var.kafka_data_disk_throughput_mbps : null
    zone           = (var.enable_availability_zones && var.kafka_vm_zone != "") ? var.kafka_vm_zone : null
  }
}
