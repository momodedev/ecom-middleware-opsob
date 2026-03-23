#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <resource-group> <vmss-name> <admin-username>" >&2
    exit 1
fi

resource_group="$1"
vmss_name="$2"
admin_user="$3"

vmss_nics=$(az vmss nic list -g "$resource_group" --vmss-name "$vmss_name")

private_ips=$(echo "$vmss_nics" | jq -r 'sort_by(.virtualMachine.id) | map(.ipConfigurations[0].privateIPAddress) | .[]')

echo "[kafka]"
index=1
while IFS= read -r ip; do
    [ -z "$ip" ] && continue
    printf 'kafka-broker-%02d ansible_host=%s private_ip=%s kafka_node_id=%d\n' "$index" "$ip" "$ip" "$index"
    index=$((index + 1))
done <<< "$private_ips"

echo "[all:vars]"
echo "ansible_user=$admin_user"
echo "ansible_ssh_private_key_file=~/.ssh/id_rsa"
echo "ansible_python_interpreter=/usr/bin/python3"

# New: also emit monitoring inventory (control node as management_node, brokers as kafka_broker)
cat > inventory/inventory.ini <<'EOF'
[management_node]
mgmt-kafka-monitor ansible_connection=local ansible_user=azureadmin

[kafka_broker]
EOF

index=1
while IFS= read -r ip; do
    [ -z "$ip" ] && continue
    printf 'kafka-broker-%02d ansible_host=%s ansible_user=%s\n' "$index" "$ip" "$admin_user" >> inventory/inventory.ini
    index=$((index + 1))
done <<< "$private_ips"




