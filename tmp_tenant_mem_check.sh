#!/usr/bin/env bash
set -euo pipefail
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "SELECT t.tenant_name, u.zone, u.max_cpu, ROUND(u.memory_size/1024/1024/1024,2) AS mem_gb FROM oceanbase.DBA_OB_UNITS u JOIN oceanbase.DBA_OB_TENANTS t ON u.tenant_id=t.tenant_id WHERE t.tenant_name='sbtest_tenant' ORDER BY u.zone;"