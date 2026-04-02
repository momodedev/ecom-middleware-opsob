#!/usr/bin/env bash
set -euo pipefail

echo "=== PRECHECK SERVERS ==="
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "SELECT svr_ip, svr_port, zone, status FROM oceanbase.GV\$OB_SERVERS ORDER BY svr_ip;"

echo "=== PRECHECK TENANTS ==="
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "SELECT tenant_name, status FROM oceanbase.DBA_OB_TENANTS ORDER BY tenant_name;"

echo "=== CHECK ANSIBLE AVAILABILITY ==="
command -v ansible || true
command -v ansible-playbook || true