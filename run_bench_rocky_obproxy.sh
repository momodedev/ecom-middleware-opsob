#!/bin/bash
# Rocky OBProxy Benchmark Runner
# Runs the OceanBase benchmark via OBProxy proxy layer

set -euo pipefail

REPO_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_OB_DIR="$REPO_PATH/ansible_ob"

if [ ! -d "$ANSIBLE_OB_DIR" ]; then
  echo "ERROR: ansible_ob directory not found at $ANSIBLE_OB_DIR"
  exit 1
fi

cd "$ANSIBLE_OB_DIR"

echo "================================================"
echo "Rocky OBProxy Benchmark Runner"
echo "================================================"
echo "Repository: $REPO_PATH"
echo "Ansible directory: $ANSIBLE_OB_DIR"
echo "Benchmark label: d8s_v5_rocky_obproxy"
echo "OBProxy endpoint: 172.17.1.7:2883"
echo "Start time: $(date)"
echo "================================================"

# Run the benchmark via OBProxy
ansible-playbook -i inventory/oceanbase_hosts playbooks/benchmark_oceanbase_sysbench.yml \
  -e "benchmark_label=d8s_v5_rocky_obproxy" \
  -e "mysql_host=172.17.1.7" \
  -e "mysql_port=2883" \
  -e "mysql_user=root@sbtest_tenant" \
  -e "mysql_password=OceanBase#!123" \
  -e "mysql_db=sbtest" \
  -v

echo ""
echo "================================================"
echo "Benchmark finished!"
echo "End time: $(date)"
echo "CSV file: /tmp/oceanbase-bench/d8s_v5_rocky_obproxy.csv"
echo "================================================"
