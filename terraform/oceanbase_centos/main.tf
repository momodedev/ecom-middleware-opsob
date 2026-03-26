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
# CentOS OceanBase observers are deployed into the same VNet/subnet/NSG as the control node
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

# Reuse control node's NSG; NSG rules are already created by terraform/oceanbase module.
# No NIC-level re-attachment needed for observer VMs.
locals {
  oceanbase_nsg_id     = data.azurerm_network_security_group.control.id
  attach_oceanbase_nsg = false
}

# NSG rules are managed by the terraform/oceanbase module (same NSG).
# Set manage_network_security_rules = true ONLY if deploying this module standalone.

resource "azurerm_network_security_rule" "centos_ob_observer_ssh" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "centos-ob-observer-ssh"
  priority                    = 300
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

resource "azurerm_network_security_rule" "centos_ob_mysql" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "centos-ob-mysql"
  priority                    = 310
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

resource "azurerm_network_security_rule" "centos_ob_rpc" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "centos-ob-rpc"
  priority                    = 320
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

resource "azurerm_network_security_rule" "centos_ob_obshell" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "centos-ob-obshell"
  priority                    = 330
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

resource "azurerm_network_security_rule" "centos_ob_monitoring" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "centos-ob-monitoring"
  priority                    = 340
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

resource "azurerm_network_security_rule" "centos_ob_grafana_public" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "centos-ob-grafana-public"
  priority                    = 350
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

resource "azurerm_network_security_rule" "centos_ob_prometheus_public" {
  count                       = var.manage_network_security_rules ? 1 : 0
  name                        = "centos-ob-prometheus-public"
  priority                    = 360
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

# NAT Gateway is managed by terraform/manage_node_ob (control-nat).
# CentOS OceanBase observers share the same subnet and use the existing NAT gateway
# for outbound internet access. No additional NAT resources needed here.

# Generate Ansible inventory from Terraform state
locals {
  ansible_inventory_path = "${path.module}/../../ansible_ob_centos/inventory/oceanbase_hosts_auto"
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
    local_file.ansible_inventory
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for CentOS OceanBase VMs to be ready..."
      
      SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${var.ssh_private_key_path}"
      
      # Initial wait for VM boot-up (Azure VMs typically take 2-3 minutes)
      echo "Waiting 120 seconds for VMs to boot..."
      sleep 120
      
      # Wait for SSH to be available on all observers
      observer_ips='${join(" ", [for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.private_ip_address])}'
      
      for ip in $observer_ips; do
        echo "Checking SSH connectivity to $ip..."
        timeout=600  # 10 minutes
        elapsed=0
        retry_count=0
        
        while [ $elapsed -lt $timeout ]; do
          if ssh $SSH_OPTS oceanadmin@$ip "echo 'SSH ready'" >/dev/null 2>&1; then
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
          exit 1
        fi
      done
      
      echo ""
      echo "✅ All CentOS OceanBase VMs are SSH accessible (pre cloud-init)."
      echo ""
      
      # ── Phase 2: Wait for cloud-init to finish on each VM ──────────
      # CentOS 7.9 cloud-init does NOT trigger a reboot (no OS upgrade).
      echo "Waiting for cloud-init to complete on all VMs..."
      for ip in $observer_ips; do
        echo "Polling cloud-init status on $ip..."
        ci_timeout=600  # 10 minutes max for cloud-init (no OS upgrade)
        ci_elapsed=0
        while [ $ci_elapsed -lt $ci_timeout ]; do
          ci_status=$(ssh $SSH_OPTS oceanadmin@$ip \
            "sudo cloud-init status 2>/dev/null | awk '/^status:/{print \$2}'" 2>/dev/null || echo "unreachable")
          
          if [ "$ci_status" = "done" ] || [ "$ci_status" = "error" ]; then
            echo "✓ Cloud-init finished on $ip (status: $ci_status)"
            break
          fi
          
          if [ $((ci_elapsed % 60)) -eq 0 ]; then
            echo "  Cloud-init still running on $ip ($ci_elapsed s elapsed, status: $ci_status)"
          fi
          
          sleep 15
          ci_elapsed=$((ci_elapsed + 15))
        done
        
        if [ $ci_elapsed -ge $ci_timeout ]; then
          echo "⚠ Cloud-init did not finish on $ip within $ci_timeout seconds – proceeding anyway"
        fi
      done
      
      # CentOS 7.9 cloud-init does NOT reboot; skip Phase 3.
      
      echo ""
      echo "✅ All CentOS OceanBase VMs ready (cloud-init done)!"
      echo "   Observer IPs: $observer_ips"
    EOT
    
    interpreter = ["/bin/bash", "-c"]
  }

  # Re-run when VMs are recreated
  triggers = {
    vm_ids = join(",", [for vm in azurerm_linux_virtual_machine.oceanbase_observers : vm.id])
  }
}

# Deploy OceanBase cluster using Ansible
resource "null_resource" "deploy_oceanbase" {
  depends_on = [
    null_resource.wait_for_ssh
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== Deploying CentOS OceanBase Cluster ==="
      
      INVENTORY_FILE="inventory/oceanbase_hosts_auto"
      PLAYBOOK_FILE="playbooks/deploy_oceanbase_playbook.yaml"
      REPO_ROOT="${path.module}/../.."
      
      cd "$REPO_ROOT/ansible_ob_centos"

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
        echo "Error: Cannot connect to CentOS OceanBase nodes via Ansible"
        exit 1
      }
      
      # Deploy OceanBase cluster
      echo "Running OceanBase deployment playbook..."
      ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" || {
        echo "Error: OceanBase deployment failed"
        exit 1
      }
      
      echo "✓ CentOS OceanBase cluster deployed successfully!"
    EOT
    
    interpreter = ["/bin/bash", "-c"]
  }
  
  triggers = {
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
      echo "=== Deploying Monitoring Stack for CentOS OceanBase Cluster ==="

      INVENTORY_FILE="inventory/oceanbase_hosts_auto"
      PLAYBOOK_FILE="playbooks/deploy_monitoring_playbook.yml"
      REPO_ROOT="${path.module}/../.."

      cd "$REPO_ROOT/ansible_ob_centos"

      if [ ! -f "$PLAYBOOK_FILE" ]; then
        echo "Error: Monitoring playbook not found at $PLAYBOOK_FILE"
        exit 1
      fi

      # Activate virtual environment if it exists
      if [ -f ~/ansible-venv/bin/activate ]; then
        source ~/ansible-venv/bin/activate
      fi

      # Run monitoring playbook with the generated inventory
      echo "Running monitoring deployment playbook..."
      ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" || {
        echo "Error: Monitoring deployment failed"
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
          exit 1
        fi
      done

      echo "✓ Monitoring deployed on control node: Grafana :3000, Prometheus :9090"
    EOT

    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    ansible_run_id = var.ansible_run_id
  }
}
