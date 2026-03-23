#!/usr/bin/env bash
# filepath: ansible/scripts/inventory_script_hosts_vms.sh

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <resource-group> <admin-username>" >&2
    exit 1
fi

resource_group="$1"
admin_user="$2"

# Get all VMs with names starting with "<resource_group>-broker-" sorted by name
vm_names=$(az vm list -g "$resource_group" --query "[?starts_with(name, '${KAFKA_VM_PREFIX}-broker-')].name" -o tsv | sort)

# Extract private IPs for each VM
private_ips=()
for vm_name in $vm_names; do
    private_ip=$(az vm list-ip-addresses -g "$resource_group" -n "$vm_name" --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)
    public_ip=$(az vm list-ip-addresses -g "$resource_group" -n "$vm_name" --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv)
    
    if [[ -z "$private_ip" || "$private_ip" == "null" ]]; then
        echo "Warning: Could not get private IP for $vm_name" >&2
        continue
    fi
    private_ips+=("$private_ip")
    # Store public IP (mapped by index/order since we iterate same list)
    if [[ -z "$public_ip" ]]; then public_ip=""; fi
    public_ips+=("$public_ip")
done

echo "[kafka]"
# Use 0-indexed naming to match Terraform/Azure VM names (<resource_group>-broker-0, <resource_group>-broker-1, etc.)
# Kafka node_id starts from 1 (KRaft requirement), but inventory names match VM indices
index=0
for ip in "${private_ips[@]}"; do
    pub="${public_ips[$index]}"
    node_id=$((index + 1))
    # Add public_ip var only if it exists
    if [[ -n "$pub" ]]; then
        printf 'kafka-broker-%d ansible_host=%s private_ip=%s public_ip=%s kafka_node_id=%d\n' "$index" "$ip" "$ip" "$pub" "$node_id"
    else
        printf 'kafka-broker-%d ansible_host=%s private_ip=%s kafka_node_id=%d\n' "$index" "$ip" "$ip" "$node_id"
    fi
    index=$((index + 1))
done

echo "[all:vars]"
echo "ansible_user=$admin_user"
echo "ansible_ssh_private_key_file=~/.ssh/id_rsa"
echo "ansible_python_interpreter=/usr/bin/python3"

# Generate monitoring inventory
cat > inventory/inventory.ini <<'EOF'
[management_node]
localhost ansible_connection=local ansible_user=azureadmin

[kafka_broker]
EOF

# Use 0-indexed naming to match VM names
index=0
for ip in "${private_ips[@]}"; do
    # IMPORTANT: Use just the IP, don't add port here - kafka_exporter role adds :9092
    printf 'kafka-broker-%d ansible_host=%s ansible_user=%s\n' "$index" "$ip" "$admin_user" >> inventory/inventory.ini
    index=$((index + 1))
done