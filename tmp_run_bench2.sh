#!/bin/bash
set -euo pipefail
cd ~/ecom-middleware-opsob
source ~/ansible-venv/bin/activate
cd ansible_ob_centos
chmod +x scripts/run_oceanbase_benchmark.sh
./scripts/run_oceanbase_benchmark.sh d8s_v5_centos 10.100.1.6 root@sbtest_tenant 'OceanBase#!123' sbtest inventory/oceanbase_hosts_auto
