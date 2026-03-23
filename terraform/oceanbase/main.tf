# Resource Group for OceanBase cluster
resource "azurerm_resource_group" "oceanbase" {
  name     = var.resource_group_name
  location = var.resource_group_location

  tags = {
    Environment = "production"
    Component   = "oceanbase-cluster"
    ManagedBy   = "terraform"
  }
}

locals {
  oceanbase_rg_name     = azurerm_resource_group.oceanbase.name
  oceanbase_rg_location = azurerm_resource_group.oceanbase.location
  oceanbase_rg_id       = azurerm_resource_group.oceanbase.id
}

# OceanBase Virtual Network
resource "azurerm_virtual_network" "oceanbase" {
  name                = var.oceanbase_vnet_name
  resource_group_name = local.oceanbase_rg_name
  location            = local.oceanbase_rg_location
  address_space       = ["10.1.0.0/16"]

  tags = {
    Environment = "production"
    Component   = "oceanbase-network"
    ManagedBy   = "terraform"
  }

  lifecycle {
    ignore_changes = [address_space, tags]
  }
}

locals {
  oceanbase_vnet_name = azurerm_virtual_network.oceanbase.name
  oceanbase_vnet_id   = azurerm_virtual_network.oceanbase.id
}

# OceanBase Subnet
resource "azurerm_subnet" "oceanbase" {
  name                         = var.oceanbase_subnet_name
  resource_group_name          = local.oceanbase_rg_name
  virtual_network_name         = local.oceanbase_vnet_name
  address_prefixes             = ["10.1.1.0/24"]
  default_outbound_access_enabled = false

  lifecycle {
    ignore_changes = [address_prefixes]
  }
}

locals {
  oceanbase_subnet_name = azurerm_subnet.oceanbase.name
  oceanbase_subnet_id   = azurerm_subnet.oceanbase.id
}

# OceanBase Network Security Group
locals {
  oceanbase_nsg_id      = var.oceanbase_nsg_id != "" ? var.oceanbase_nsg_id : azurerm_network_security_group.oceanbase[0].id
  oceanbase_nsg_rg_name = var.oceanbase_nsg_id != "" ? split("/", var.oceanbase_nsg_id)[4] : local.oceanbase_rg_name
  oceanbase_nsg_name    = var.oceanbase_nsg_id != "" ? split("/", var.oceanbase_nsg_id)[8] : azurerm_network_security_group.oceanbase[0].name
  attach_oceanbase_nsg  = var.oceanbase_nsg_id != "" || true
}

resource "azurerm_network_security_group" "oceanbase" {
  count               = var.oceanbase_nsg_id != "" ? 0 : 1
  name                = var.oceanbase_nsg_name
  location            = local.oceanbase_rg_location
  resource_group_name = local.oceanbase_rg_name

  security_rule {
    name                       = "mysql"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.oceanbase_mysql_port)
    source_address_prefixes    = var.oceanbase_allowed_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "rpc"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2882"
    source_address_prefixes    = var.oceanbase_allowed_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "obshell"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "2886"
    source_address_prefixes    = var.oceanbase_allowed_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ssh"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.ssh_allowed_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "monitoring"
    priority                   = 140
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["9100", "9308"]
    source_address_prefixes    = var.oceanbase_allowed_cidrs
    destination_address_prefix = "*"
  }

  tags = {
    Environment = "production"
    Component   = "oceanbase-nsg"
    ManagedBy   = "terraform"
  }
}

resource "azurerm_subnet_network_security_group_association" "oceanbase" {
  count                     = local.attach_oceanbase_nsg ? 1 : 0
  subnet_id                 = local.oceanbase_subnet_id
  network_security_group_id = local.oceanbase_nsg_id
}

# NAT Gateway for outbound internet access
resource "azurerm_nat_gateway" "oceanbase" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "oceanbase-nat"
  location            = local.oceanbase_rg_location
  resource_group_name = local.oceanbase_rg_name

  tags = {
    Environment = "production"
    Component   = "oceanbase-nat"
    ManagedBy   = "terraform"
  }
}

resource "azurerm_subnet_nat_gateway_association" "oceanbase" {
  count             = var.enable_nat_gateway ? 1 : 0
  subnet_id         = local.oceanbase_subnet_id
  nat_gateway_id    = azurerm_nat_gateway.oceanbase[0].id
}

# VNet Peering with Control Node (for Ansible deployment)
resource "azurerm_virtual_network_peering" "oceanbase_to_control" {
  count                       = var.enable_vnet_peering && var.deploy_mode == "together" ? 1 : 0
  name                        = "oceanbase-to-control"
  resource_group_name         = local.oceanbase_rg_name
  virtual_network_name        = local.oceanbase_vnet_name
  remote_virtual_network_id   = "/subscriptions/${var.ARM_SUBSCRIPTION_ID}/resourceGroups/${var.control_resource_group_name}/providers/Microsoft.Network/virtualNetworks/${var.control_vnet_name}"
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
}

# Generate Ansible inventory from Terraform state
locals {
  ansible_inventory_path = "${path.module}/../../ansible/inventory/oceanbase_hosts_auto"
  observer_ips_json      = jsonencode([for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.private_ip_address])
  observer_names         = [for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.name]
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory_template.tftpl", {
    observer_ips       = local.observer_ips_json
    observer_names     = local.observer_names
    instance_count     = var.oceanbase_instance_count
    cluster_name       = var.oceanbase_cluster_name
    root_password      = var.oceanbase_root_password
    memory_limit       = var.oceanbase_memory_limit
    cpu_count          = var.oceanbase_cpu_count
    mysql_port         = var.oceanbase_mysql_port
    ssh_user           = "oceanadmin"
    ssh_key_path       = var.ssh_private_key_path
  })
  filename = local.ansible_inventory_path
}

# Wait for VMs to be ready and SSH accessible
resource "null_resource" "wait_for_ssh" {
  depends_on = [
    azurerm_linux_virtual_machine.oceanbase_observers,
    local_file.ansible_inventory
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for OceanBase VMs to be ready..."
      sleep 60
      
      # Wait for SSH to be available on all observers
      for ip in $(echo '${join(",", [for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.private_ip_address])}' | tr ',' ' '); do
        echo "Checking SSH connectivity to $ip..."
        timeout=300
        elapsed=0
        while [ $elapsed -lt $timeout ]; do
          if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} oceanadmin@$ip "echo 'SSH ready'" 2>/dev/null; then
            echo "✓ SSH ready on $ip"
            break
          fi
          echo "Waiting for SSH on $ip... ($elapsed seconds)"
          sleep 10
          elapsed=$((elapsed + 10))
        done
        
        if [ $elapsed -ge $timeout ]; then
          echo "✗ Timeout waiting for SSH on $ip"
          exit 1
        fi
      done
      
      echo "All OceanBase VMs are SSH accessible!"
    EOT
  }
}

# Deploy OceanBase cluster using Ansible
resource "null_resource" "deploy_oceanbase" {
  depends_on = [
    null_resource.wait_for_ssh,
    azurerm_virtual_network_peering.oceanbase_to_control
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Deploying OceanBase Cluster ==="
      
      INVENTORY_FILE="${local.ansible_inventory_path}"
      PLAYBOOK_FILE="${path.module}/../../ansible/playbooks/deploy_oceanbase_cluster.yml"
      REPO_ROOT="${path.module}/../.."
      
      cd "$REPO_ROOT/ansible"
      
      # Activate virtual environment if it exists
      if [ -f ~/ansible-venv/bin/activate ]; then
        source ~/ansible-venv/bin/activate
      fi
      
      # Verify Ansible connectivity
      echo "Verifying Ansible connectivity..."
      ansible all -i "$INVENTORY_FILE" -m ping || {
        echo "Error: Cannot connect to OceanBase nodes via Ansible"
        exit 1
      }
      
      # Deploy OceanBase cluster
      echo "Running OceanBase deployment playbook..."
      ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" || {
        echo "Error: OceanBase deployment failed"
        exit 1
      }
      
      echo "✓ OceanBase cluster deployed successfully!"
    EOT
    
    interpreter = ["/bin/bash", "-c"]
  }
  
  triggers = {
    always_run = timestamp()
    ansible_run_id = var.ansible_run_id
  }
}

# Deploy monitoring tools (Grafana & Prometheus) on control node
resource "null_resource" "deploy_monitoring" {
  depends_on = [
    null_resource.deploy_oceanbase
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Deploying Monitoring Stack ==="
      
      PLAYBOOK_FILE="${path.module}/../../ansible/playbooks/deploy_monitoring_playbook.yml"
      INVENTORY_FILE="${path.module}/../../ansible/inventory/control_node"
      REPO_ROOT="${path.module}/../.."
      
      cd "$REPO_ROOT/ansible"
      
      # Activate virtual environment if it exists
      if [ -f ~/ansible-venv/bin/activate ]; then
        source ~/ansible-venv/bin/activate
      fi
      
      # Check if control node inventory exists
      if [ ! -f "$INVENTORY_FILE" ]; then
        echo "Warning: Control node inventory not found at $INVENTORY_FILE"
        echo "Skipping monitoring deployment. You can deploy manually later."
        echo "Run: ansible-playbook -i $INVENTORY_FILE $PLAYBOOK_FILE"
        exit 0
      fi
      
      # Deploy monitoring stack
      echo "Running monitoring deployment playbook..."
      ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" || {
        echo "Warning: Monitoring deployment encountered errors"
        echo "You can retry manually: ansible-playbook -i $INVENTORY_FILE $PLAYBOOK_FILE"
      }
      
      echo "✓ Monitoring stack deployment completed!"
    EOT
    
    interpreter = ["/bin/bash", "-c"]
  }
  
  triggers = {
    always_run = timestamp()
    ansible_run_id = var.ansible_run_id
  }
}
