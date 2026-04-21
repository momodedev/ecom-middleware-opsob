output "public_ip_address" {
  description = "Public IP of the OceanBase standalone VM. Use this for SSH and Ansible inventory."
  value       = azurerm_public_ip.pip.ip_address
}

output "private_ip_address" {
  description = "Private IP of the OceanBase standalone VM."
  value       = azurerm_network_interface.nic.private_ip_address
}

output "vm_name" {
  description = "Name of the OceanBase standalone VM."
  value       = azurerm_linux_virtual_machine.ob_standalone.name
}

output "resource_group_name" {
  description = "Resource group containing all standalone resources."
  value       = local.rg_name
}

output "ansible_inventory_snippet" {
  description = "Paste this into ansible/inventory.ini to run the playbook."
  sensitive   = true
  value       = <<-EOT
    [ob_standalone]
    ${azurerm_public_ip.pip.ip_address} ansible_user=${var.admin_username} ansible_port=22 ansible_ssh_private_key_file=${var.ssh_private_key_path}
  EOT
}

output "ssh_command" {
  description = "SSH command to connect to the VM."
  sensitive   = true
  value       = "ssh -i ${var.ssh_private_key_path} ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}

output "mysql_connect_command" {
  description = "MySQL connection command once OceanBase is deployed."
  value       = "mysql -h${azurerm_public_ip.pip.ip_address} -P2881 -uroot@sys -p"
}
