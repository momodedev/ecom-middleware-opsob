#!/bin/bash
set -euo pipefail
cd ~/ecom-middleware-opsob
git pull origin t3
source ~/ansible-venv/bin/activate

# Query Rocky cluster observer IPs
echo "=== Rocky OceanBase Cluster Observers ==="
mysql -h 172.17.1.6 -P 2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -N \
  -e "SELECT svr_ip, zone, status FROM __all_server ORDER BY zone;"

echo ""
echo "=== Checking for existing inventory ==="
ls -la ~/ecom-middleware-opsob/ansible_ob/inventory/

# Create inventory if it doesn't exist
if [ ! -f ~/ecom-middleware-opsob/ansible_ob/inventory/oceanbase_hosts_auto ]; then
  echo ""
  echo "=== Generating inventory from cluster info ==="
  # Get IPs from cluster
  OBSERVER_IPS=$(mysql -h 172.17.1.6 -P 2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -N \
    -e "SELECT svr_ip FROM __all_server ORDER BY zone;" 2>/dev/null)
  
  IDX=0
  cat > ~/ecom-middleware-opsob/ansible_ob/inventory/oceanbase_hosts_auto << 'HEADER'
# OceanBase Rocky Cluster Inventory (auto-generated)
[oceanbase]
HEADER
  
  while IFS= read -r ip; do
    echo "ob-observer-${IDX} ansible_host=${ip} private_ip=${ip}" >> ~/ecom-middleware-opsob/ansible_ob/inventory/oceanbase_hosts_auto
    IDX=$((IDX + 1))
  done <<< "$OBSERVER_IPS"
  
  cat >> ~/ecom-middleware-opsob/ansible_ob/inventory/oceanbase_hosts_auto << 'VARS'

[oceanbase:vars]
ansible_user=oceanadmin
ansible_ssh_private_key_file=~/.ssh/id_rsa
ansible_python_interpreter=/usr/bin/python3
VARS
  
  echo "Inventory created:"
  cat ~/ecom-middleware-opsob/ansible_ob/inventory/oceanbase_hosts_auto
else
  echo "Inventory already exists:"
  cat ~/ecom-middleware-opsob/ansible_ob/inventory/oceanbase_hosts_auto
fi

echo ""
echo "=== Running benchmark ==="
cd ansible_ob
chmod +x scripts/run_oceanbase_benchmark.sh
./scripts/run_oceanbase_benchmark.sh d8s_v6_rocky 172.17.1.6 root@sbtest_tenant 'OceanBase#!123' sbtest inventory/oceanbase_hosts_auto
