#!/bin/bash
source ~/ansible-venv/bin/activate
cd ~/ecom-middleware-opsob/ansible_ob_centos
LABEL=$(date -u +%Y%m%dT%H%M%SZ)_d8s_v5_centos
echo "Starting benchmark with label: $LABEL"
ansible-playbook -i inventory/oceanbase_hosts_auto playbooks/benchmark_oceanbase_sysbench.yml -e benchmark_label=$LABEL -v
