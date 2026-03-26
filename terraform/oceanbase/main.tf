# Use existing resource group (managed by terraform/manage_node_ob)
data "azurerm_resource_group" "oceanbase" {
  name = var.resource_group_name
}

locals {
  oceanbase_rg_name     = data.azurerm_resource_group.oceanbase.name
  oceanbase_rg_location = data.azurerm_resource_group.oceanbase.location
  oceanbase_rg_id       = data.azurerm_resource_group.oceanbase.id
}

# Look up existing control-node VNet/subnet/NSG
# OceanBase observers are deployed into the same VNet/subnet/NSG as the control node
data "azurerm_virtual_network" "control" {
  name                = var.control_vnet_name
  resource_group_name = var.control_resource_group_name
}

data "azurerm_subnet" "control" {
  name                 = var.control_subnet_name
  virtual_network_name = var.control_vnet_name
  resource_group_name  = var.control_resource_group_name
}

data "azurerm_network_security_group" "control" {
  name                = var.control_nsg_name
  resource_group_name = var.control_resource_group_name
}

locals {
  oceanbase_vnet_name   = data.azurerm_virtual_network.control.name
  oceanbase_vnet_id     = data.azurerm_virtual_network.control.id
  oceanbase_subnet_name = data.azurerm_subnet.control.name
  oceanbase_subnet_id   = data.azurerm_subnet.control.id
}

# Reuse control node's NSG; add OceanBase-specific inbound rules to it
locals {
  oceanbase_nsg_id     = data.azurerm_network_security_group.control.id
  # control-ob-nsg is already associated with control-ob-subnet at subnet level;
  # no NIC-level re-attachment needed for observer VMs
  attach_oceanbase_nsg = false
}

# Allow SSH to observer VMs from within the VNet (required for Ansible from control node)
resource "azurerm_network_security_rule" "ob_observer_ssh" {
  name                        = "ob-observer-ssh"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = var.control_resource_group_name
  network_security_group_name = var.control_nsg_name
}

resource "azurerm_network_security_rule" "ob_mysql" {
  name                        = "ob-mysql"
  priority                    = 210
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.oceanbase_mysql_port)
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = var.control_resource_group_name
  network_security_group_name = var.control_nsg_name
}

resource "azurerm_network_security_rule" "ob_rpc" {
  name                        = "ob-rpc"
  priority                    = 220
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "2882"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = var.control_resource_group_name
  network_security_group_name = var.control_nsg_name
}

resource "azurerm_network_security_rule" "ob_obshell" {
  name                        = "ob-obshell"
  priority                    = 230
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "2886"
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = var.control_resource_group_name
  network_security_group_name = var.control_nsg_name
}

resource "azurerm_network_security_rule" "ob_monitoring" {
  name                        = "ob-monitoring"
  priority                    = 240
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["9100", "9308"]
  source_address_prefix       = "VirtualNetwork"
  destination_address_prefix  = "*"
  resource_group_name         = var.control_resource_group_name
  network_security_group_name = var.control_nsg_name
}

# Allow external access to Grafana on control node public IP.
resource "azurerm_network_security_rule" "ob_grafana_public" {
  name                        = "ob-grafana-public"
  priority                    = 250
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3000"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.control_resource_group_name
  network_security_group_name = var.control_nsg_name
}

# Allow external access to Prometheus on control node public IP.
resource "azurerm_network_security_rule" "ob_prometheus_public" {
  name                        = "ob-prometheus-public"
  priority                    = 260
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "9090"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.control_resource_group_name
  network_security_group_name = var.control_nsg_name
}

# NAT Gateway - provides outbound internet for observer VMs (which have no public IPs)
# The control node's own public IP handles its outbound traffic; NAT only affects VMs without one.
resource "azurerm_public_ip" "oceanbase_nat" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "oceanbase-nat-ip"
  location            = local.oceanbase_rg_location
  resource_group_name = local.oceanbase_rg_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment = "production"
    Component   = "oceanbase-nat"
    ManagedBy   = "terraform"
  }
}

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
  count          = var.enable_nat_gateway ? 1 : 0
  subnet_id      = local.oceanbase_subnet_id
  nat_gateway_id = azurerm_nat_gateway.oceanbase[0].id
}

resource "azurerm_nat_gateway_public_ip_association" "oceanbase" {
  count                = var.enable_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.oceanbase[0].id
  public_ip_address_id = azurerm_public_ip.oceanbase_nat[0].id
}

# VNet peering removed: OceanBase observers are now in the same VNet as the control node.

# Generate Ansible inventory from Terraform state
locals {
  ansible_inventory_path = "${path.module}/../../ansible_ob/inventory/oceanbase_hosts_auto"
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
    azurerm_virtual_machine_data_disk_attachment.oceanbase_data,
    azurerm_virtual_machine_data_disk_attachment.oceanbase_redo,
    azurerm_network_security_rule.ob_observer_ssh,
    azurerm_subnet_nat_gateway_association.oceanbase,
    local_file.ansible_inventory
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for OceanBase VMs to be ready..."
      
      # Initial wait for VM boot-up (Azure VMs typically take 2-3 minutes)
      echo "Waiting 120 seconds for VMs to boot..."
      sleep 120
      
      # Wait for SSH to be available on all observers
      observer_ips='${join(" ", [for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.private_ip_address])}'
      
      for ip in $observer_ips; do
        echo "Checking SSH connectivity to $ip..."
        timeout=600  # Increased to 10 minutes
        elapsed=0
        retry_count=0
        
        while [ $elapsed -lt $timeout ]; do
          # Try SSH connection
          if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${var.ssh_private_key_path} oceanadmin@$ip "echo 'SSH ready'" >/dev/null 2>&1; then
            echo "✓ SSH ready on $ip"
            break
          fi
          
          retry_count=$((retry_count + 1))
          if [ $((retry_count % 6)) -eq 0 ]; then
            echo "  Still waiting for SSH on $ip... ($elapsed seconds elapsed)"
          fi
          
          sleep 10
          elapsed=$((elapsed + 10))
        done
        
        if [ $elapsed -ge $timeout ]; then
          echo "✗ Timeout waiting for SSH on $ip after $timeout seconds"
          echo ""
          echo "Troubleshooting:"
          echo "  1. Check VM status: az vm show -g control-ob-rg -n <observer-vm-name> -d"
          echo "  2. Check NSG rules: az network nsg rule list -g control-ob-rg --nsg-name oceanbase-nsg"
          echo "  3. Verify SSH key permissions: chmod 600 ${var.ssh_private_key_path}"
          exit 1
        fi
      done
      
      echo ""
      echo "✅ All OceanBase VMs are SSH accessible!"
      echo "   Observer IPs: $observer_ips"
    EOT
    
    interpreter = ["/bin/bash", "-c"]
  }
}

# Deploy OceanBase cluster using Ansible
resource "null_resource" "deploy_oceanbase" {
  depends_on = [
    null_resource.wait_for_ssh
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Deploying OceanBase Cluster ==="
      
      # Paths below are relative to ansible_ob/ after cd.
      INVENTORY_FILE="inventory/oceanbase_hosts_auto"
      PLAYBOOK_FILE="playbooks/deploy_oceanbase_playbook.yaml"
      REPO_ROOT="${path.module}/../.."
      
      cd "$REPO_ROOT/ansible_ob"

      if [ ! -f "$INVENTORY_FILE" ]; then
        echo "Error: Inventory file not found at $INVENTORY_FILE"
        exit 1
      fi

      if [ ! -f "$PLAYBOOK_FILE" ]; then
        echo "Error: Playbook not found at $PLAYBOOK_FILE"
        exit 1
      fi
      
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
    ansible_run_id = var.ansible_run_id
  }
}

# Deploy monitoring tools (Grafana & Prometheus) on control node
# Deploy monitoring tools (Grafana & Prometheus) on this control node (localhost).
# terraform apply runs ON the control node, so local-exec installs monitoring directly here.
resource "null_resource" "deploy_monitoring" {
  depends_on = [
    null_resource.deploy_oceanbase
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Deploying Monitoring Stack (Grafana + Prometheus) on control node ==="

      # Path below is relative to ansible_ob/ after cd.
      PLAYBOOK_FILE="playbooks/deploy_monitoring_playbook.yml"
      REPO_ROOT="${path.module}/../.."

      cd "$REPO_ROOT/ansible_ob"

      if [ ! -f "$PLAYBOOK_FILE" ]; then
        echo "Error: Monitoring playbook not found at $PLAYBOOK_FILE"
        exit 1
      fi

      # Activate virtual environment if it exists
      if [ -f ~/ansible-venv/bin/activate ]; then
        source ~/ansible-venv/bin/activate
      fi

      # Generate a temporary monitoring inventory:
      #   management_node = this control node (running Terraform, so localhost)
      #   oceanbase_observer = OceanBase observer IPs (Prometheus scrape targets for node_exporter)
      MONITORING_INVENTORY="/tmp/ob_monitoring_inventory_$$.ini"

      echo "[management_node]" > "$MONITORING_INVENTORY"
      echo "localhost ansible_connection=local" >> "$MONITORING_INVENTORY"
      echo "" >> "$MONITORING_INVENTORY"
      echo "[oceanbase_observer]" >> "$MONITORING_INVENTORY"
      for ip in ${join(" ", [for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.private_ip_address])}; do
        echo "$ip ansible_host=$ip ansible_user=oceanadmin ansible_ssh_private_key_file=${var.ssh_private_key_path}" >> "$MONITORING_INVENTORY"
      done

      echo "Monitoring inventory:"
      cat "$MONITORING_INVENTORY"

      # Install Prometheus + Grafana on this control node
      echo "Running monitoring deployment playbook..."
      ansible-playbook -i "$MONITORING_INVENTORY" "$PLAYBOOK_FILE" || {
        echo "Error: Monitoring deployment failed"
        echo "Retry: ansible-playbook -i $MONITORING_INVENTORY $PLAYBOOK_FILE -v"
        rm -f "$MONITORING_INVENTORY"
        exit 1
      }

      # Verify local endpoints are actually listening before reporting success.
      for endpoint in 3000 9090; do
        timeout=180
        elapsed=0

        while [ $elapsed -lt $timeout ]; do
          if curl -fsS "http://127.0.0.1:$endpoint" >/dev/null 2>&1; then
            echo "✓ Endpoint ready on :$endpoint"
            break
          fi

          sleep 5
          elapsed=$((elapsed + 5))
        done

        if [ $elapsed -ge $timeout ]; then
          echo "Error: Endpoint :$endpoint is not reachable on control node"
          rm -f "$MONITORING_INVENTORY"
          exit 1
        fi
      done

      rm -f "$MONITORING_INVENTORY"
      echo "✓ Monitoring deployed on control node: Grafana :3000, Prometheus :9090"
    EOT

    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    ansible_run_id = var.ansible_run_id
  }
}
