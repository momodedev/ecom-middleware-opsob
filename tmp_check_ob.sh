#!/bin/bash
# Check partition/tablet leader distribution

which mysql >/dev/null 2>&1 || sudo dnf install -y mariadb >/dev/null 2>&1

echo "=== Leader Distribution by Server ==="
mysql -h172.17.1.7 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "
SELECT svr_ip, role, COUNT(*) as cnt
FROM oceanbase.__all_virtual_ls_meta_table
GROUP BY svr_ip, role
ORDER BY svr_ip, role;
"

echo "=== sys tenant primary_zone ==="
mysql -h172.17.1.7 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "
SELECT tenant_id, tenant_name, primary_zone, locality FROM __all_tenant;
"

echo "=== Unit config (sys_pool resources) ==="
mysql -h172.17.1.7 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "
SELECT uc.unit_config_id, uc.name, uc.max_cpu, uc.min_cpu, uc.memory_size, uc.log_disk_size
FROM oceanbase.__all_unit_config uc;
"

echo "=== Check if user tenants exist ==="
mysql -h172.17.1.7 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "
SELECT tenant_id, tenant_name, primary_zone, locality FROM __all_tenant WHERE tenant_id > 1;
"
