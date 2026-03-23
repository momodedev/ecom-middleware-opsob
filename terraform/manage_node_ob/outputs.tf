# Terraform Outputs for Control Node Deployment
# These outputs provide useful information about deployed resources

output "resource_group_name" {
  description = "Name of the resource group containing control node resources."
  value       = local.resource_group_name
}

output "resource_group_location" {
  description = "Azure region where resources are deployed."
  value       = local.resource_group_location
}

output "control_public_ip" {
  description = "Public IP address of the control node VM."
  value       = try(data.azapi_resource.pip_existing.id, "") != "" ? jsondecode(data.azapi_resource.pip_existing.output).properties.ipAddress : azurerm_public_ip.control[0].ip_address
}

output "control_private_ip" {
  description = "Private IP address of the control node VM."
  value       = try(data.azapi_resource.nic_existing.id, "") != "" ? jsondecode(data.azapi_resource.nic_existing.output).properties.ipConfigurations[0].properties.privateIPAddress : azurerm_network_interface.example[0].private_ip_address
}

output "control_vm_name" {
  description = "Name of the control node virtual machine."
  value       = local.control_vm_id != "" ? (try(data.azapi_resource.vm_existing.id, "") != "" ? data.azapi_resource.vm_existing.name : azurerm_linux_virtual_machine.example[0].name) : "not-created"
}

output "control_vm_size" {
  description = "Azure VM size of the control node."
  value       = var.control_vm_size
}

output "control_nic_id" {
  description = "Resource ID of the control node network interface."
  value       = local.control_nic_id
}

output "control_subnet_id" {
  description = "Resource ID of the control subnet."
  value       = local.control_subnet_id
}

output "control_vnet_name" {
  description = "Name of the control virtual network."
  value       = local.control_vnet_name
}

output "control_nsg_id" {
  description = "Resource ID of the network security group attached to control subnet."
  value       = local.control_nsg_id
}

output "ssh_command" {
  description = "SSH command to connect to the control node."
  value       = "ssh -p ${var.control_ssh_port} azureadmin@${try(data.azapi_resource.pip_existing.id, "") != "" ? jsondecode(data.azapi_resource.pip_existing.output).properties.ipAddress : azurerm_public_ip.control[0].ip_address}"
}

output "grafana_url" {
  description = "URL to access Grafana dashboard."
  value       = "http://${try(data.azapi_resource.pip_existing.id, "") != "" ? jsondecode(data.azapi_resource.pip_existing.output).properties.ipAddress : azurerm_public_ip.control[0].ip_address}:3000"
}

output "prometheus_url" {
  description = "URL to access Prometheus metrics server."
  value       = "http://${try(data.azapi_resource.pip_existing.id, "") != "" ? jsondecode(data.azapi_resource.pip_existing.output).properties.ipAddress : azurerm_public_ip.control[0].ip_address}:9090"
}

output "control_managed_identity_principal_id" {
  description = "Principal ID of the control node's managed identity."
  value       = local.control_vm_principal_id
}

output "ansible_venv_path" {
  description = "Path to Ansible virtual environment on control node."
  value       = "/home/azureadmin/ansible-venv"
}

output "deploy_mode" {
  description = "Deployment mode used (together or separate)."
  value       = var.deploy_mode
}

output "existing_resources_summary" {
  description = "Summary of existing resources found in Azure"
  value = {
    resource_group_exists   = try(data.azapi_resource.rg_existing.id, "") != ""
    vnet_exists             = try(data.azapi_resource.vnet_existing.id, "") != ""
    subnet_exists           = try(data.azapi_resource.subnet_existing.id, "") != ""
    nsg_exists              = try(data.azapi_resource.nsg_existing.id, "") != "" || var.control_nsg_id != ""
    public_ip_exists        = try(data.azapi_resource.pip_existing.id, "") != ""
    nic_exists              = try(data.azapi_resource.nic_existing.id, "") != ""
    vm_exists               = try(data.azapi_resource.vm_existing.id, "") != ""
    role_assignment_exists  = true  # Always considered exists if VM exists since we can't check
  }
}
