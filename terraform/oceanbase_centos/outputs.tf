# Terraform Outputs for OceanBase Cluster Deployment

output "resource_group_name" {
  description = "Name of the resource group containing OceanBase resources."
  value       = local.oceanbase_rg_name
}

output "resource_group_location" {
  description = "Azure region where OceanBase resources are deployed."
  value       = local.oceanbase_rg_location
}

output "oceanbase_vnet_name" {
  description = "Name of the OceanBase virtual network."
  value       = local.oceanbase_vnet_name
}

output "oceanbase_subnet_id" {
  description = "Resource ID of the OceanBase subnet."
  value       = local.oceanbase_subnet_id
}

output "oceanbase_nsg_id" {
  description = "Resource ID of the Network Security Group attached to OceanBase subnet."
  value       = local.oceanbase_nsg_id
}

output "observer_vm_names" {
  description = "Names of the OceanBase observer VMs."
  value       = [for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.name]
}

output "observer_private_ips" {
  description = "Private IP addresses of OceanBase observer VMs."
  value       = [for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.private_ip_address]
}

output "observer_public_ips" {
  description = "Public IP addresses (if any) of OceanBase observer VMs."
  value       = [for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.public_ip_address]
}

output "observer_vm_ids" {
  description = "Resource IDs of OceanBase observer VMs."
  value       = [for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.id]
}

output "data_disk_ids" {
  description = "Resource IDs of OceanBase data disks."
  value       = [for disk in azurerm_managed_disk.oceanbase_data : disk.id]
}

output "redo_disk_ids" {
  description = "Resource IDs of OceanBase redo log disks."
  value       = [for disk in azurerm_managed_disk.oceanbase_redo : disk.id]
}

output "oceanbase_connection_info" {
  description = "Connection information for OceanBase cluster."
  value = {
    cluster_name    = var.oceanbase_cluster_name
    mysql_port      = var.oceanbase_mysql_port
    rpc_port        = 2882
    obshell_port    = 2886
    root_password   = var.oceanbase_root_password
    private_ips     = join(",", [for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.private_ip_address])
    ssh_user        = "oceanadmin"
    ssh_command     = "ssh -i ${var.ssh_private_key_path} oceanadmin@<observer-private-ip>"
  }
  sensitive = true
}

output "monitoring_urls" {
  description = "Monitoring dashboard URLs (available after Ansible deployment)."
  value = {
    grafana   = "http://<control-node-ip>:3000"
    prometheus = "http://<control-node-ip>:9090"
  }
}

output "deployment_summary" {
  description = "Summary of deployed OceanBase resources."
  value = {
    resource_group      = local.oceanbase_rg_name
    location            = local.oceanbase_rg_location
    observer_count      = var.oceanbase_instance_count
    vm_size             = var.oceanbase_vm_size
    data_disk_size_gb   = var.oceanbase_data_disk_size_gb
    redo_disk_size_gb   = var.oceanbase_redo_disk_size_gb
    availability_zones  = var.enable_availability_zones
    vnet_peering_enabled = var.enable_vnet_peering && var.deploy_mode == "together"
  }
}

output "deployment_status" {
  description = "Automated deployment status and next steps."
  value = {
    infrastructure_deployed = true
    oceanbase_deployed      = null_resource.deploy_oceanbase.id != ""
    monitoring_deployed     = null_resource.deploy_monitoring.id != ""
    
    connection_info = {
      cluster_name    = var.oceanbase_cluster_name
      mysql_port      = var.oceanbase_mysql_port
      rpc_port        = 2882
      obshell_port    = 2886
      root_password   = var.oceanbase_root_password
      private_ips     = join(",", [for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.private_ip_address])
      ssh_user        = "oceanadmin"
      ssh_command     = "ssh -i ${var.ssh_private_key_path} oceanadmin@<observer-private-ip>"
    }
    
    monitoring_access = {
      grafana_url     = "http://<control-node-public-ip>:3000"
      prometheus_url  = "http://<control-node-public-ip>:9090"
      default_user    = "admin"
      default_password = "admin"
    }
    
    next_steps = [
      "1. SSH to any observer: ssh -i ${var.ssh_private_key_path} oceanadmin@${azurerm_linux_virtual_machine.oceanbase_observers[0].private_ip_address}",
      "2. Switch to admin user: su - admin",
      "3. Load OceanBase environment: source ~/.oceanbase-all-in-one/bin/env.sh",
      "4. List clusters: obd cluster list",
      "5. Display cluster: obd cluster display ${var.oceanbase_cluster_name}",
      "6. Connect to database: obclient -h127.0.0.1 -P${var.oceanbase_mysql_port} -uroot@sys -p'${var.oceanbase_root_password}' -Doceanbase -A",
      "7. Access Grafana: http://<control-node-public-ip>:3000 (admin/admin)"
    ]
  }
  sensitive = true
}
