#!/bin/bash
# Query OceanBase via mysql from control node (management node has mariadb)

# Install mariadb client if not present
which mysql >/dev/null 2>&1 || sudo dnf install -y mariadb >/dev/null 2>&1

echo "=== Server List ==="
mysql -h172.17.1.7 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "SELECT svr_ip, svr_port, zone, status, with_rootserver FROM __all_server;"

echo "=== Tenant List ==="
mysql -h172.17.1.7 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "SELECT tenant_id, tenant_name, primary_zone, locality FROM __all_tenant;"

echo "=== Unit Placement ==="
mysql -h172.17.1.7 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "SELECT unit_id, resource_pool_id, svr_ip, zone FROM __all_unit;"

echo "=== Resource Pools ==="
mysql -h172.17.1.7 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "SELECT resource_pool_id, name, unit_count, tenant_id, zone_list FROM __all_resource_pool;"

echo "=== Balance Parameters ==="
mysql -h172.17.1.7 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "SHOW PARAMETERS LIKE 'enable_rebalance';"
mysql -h172.17.1.7 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "SHOW PARAMETERS LIKE 'primary_zone';"

echo "=== Benchmark tenant (sbtest) check ==="
mysql -h172.17.1.7 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "SELECT tenant_id, tenant_name, primary_zone, locality FROM __all_tenant WHERE tenant_name='sbtest' OR tenant_name='test';" 2>&1

echo "=== Check database sbtest ==="
mysql -h172.17.1.7 -P2881 -uroot@sys -p'OceanBase#!123' -e "SELECT database_id, database_name, tenant_id FROM oceanbase.__all_virtual_database WHERE database_name='sbtest';" 2>&1
