#!/bin/bash
set -uo pipefail

# sys tenant works, tenant login needs special handling
run_sys() {
  mysql -h 10.100.1.6 -P 2881 -uroot@sys -p'OceanBase#!123' -Doceanbase "$@"
}

echo "===== 1. CLUSTER OVERVIEW ====="
run_sys -e "SELECT svr_ip, zone, status, WITH_ROOTSERVER FROM __all_server ORDER BY zone;"

echo ""
echo "===== 2. ALL TENANTS ====="
run_sys -e "SELECT tenant_id, tenant_name, zone_list, primary_zone, locality, compatibility_mode FROM __all_tenant;"

echo ""
echo "===== 3. RESOURCE POOLS ====="
run_sys -e "SELECT name, unit_count, unit_config_id, zone_list, tenant_id FROM __all_resource_pool;"

echo ""
echo "===== 4. UNIT CONFIGS (all columns) ====="
run_sys -e "SELECT * FROM __all_unit_config\G"

echo ""
echo "===== 5. TENANT UNITS PLACEMENT ====="
run_sys -e "SELECT t.tenant_name, u.svr_ip, u.zone, u.unit_id, u.resource_pool_id FROM __all_unit u JOIN __all_resource_pool p ON u.resource_pool_id = p.resource_pool_id JOIN __all_tenant t ON t.tenant_id = p.tenant_id ORDER BY t.tenant_name, u.zone;"

echo ""
echo "===== 6. CLUSTER PARAMETERS WITH VALUES ====="
run_sys -e "SHOW PARAMETERS LIKE 'memory_limit'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'memory_limit_percentage'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'system_memory'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'cpu_count'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'datafile_size'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'datafile_disk_percentage'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'log_disk_size'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'log_disk_percentage'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'enable_syslog_recycle'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'max_syslog_file_count'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'syslog_level'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'net_thread_count'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'writing_throttling_trigger_percentage'\G" | grep -E "name|value|zone|svr_ip"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'enable_sql_audit'\G" | grep -E "name|value|zone|svr_ip"

echo ""
echo "===== 7. SBTEST_TENANT LOGIN CHECK ====="
# Try login via sys tenant to check sbtest_tenant password
run_sys -N -e "SELECT tenant_id, tenant_name FROM __all_tenant WHERE tenant_name='sbtest_tenant';"

# Check if password works with explicit escaping
mysql -h 10.100.1.6 -P 2881 -u'root@sbtest_tenant' -p'OceanBase#!123' -e "SELECT 1 AS login_ok;" 2>&1

echo ""
echo "===== 8. SBTEST_TENANT CONFIG (via sys) ====="
# Get tenant variables via sys tenant virtual tables
run_sys -e "SELECT name, value FROM __all_virtual_sys_variable WHERE tenant_id=(SELECT tenant_id FROM __all_tenant WHERE tenant_name='sbtest_tenant') AND name IN ('ob_query_timeout','ob_trx_timeout','ob_trx_idle_timeout','max_connections','ob_plan_cache_percentage','parallel_servers_target','ob_sql_work_area_percentage');" 2>/dev/null || echo "(virtual sys variable table not accessible)"

echo ""
echo "===== 9. OCEANBASE VERSION ====="
run_sys -N -e "SELECT value FROM __all_virtual_sys_parameter_stat WHERE name='min_observer_version' LIMIT 1;" 2>/dev/null || \
run_sys -e "SHOW PARAMETERS LIKE 'min_observer_version'\G" 2>/dev/null | grep value || \
run_sys -N -e "SELECT version();"

echo ""
echo "===== 10. OBSERVER RESOURCE STATS ====="
run_sys -e "DESC __all_virtual_server_stat;" 2>/dev/null | head -30 || echo "(table not found)"

echo ""
echo "===== 11. GV VIEWS FOR RESOURCES ====="
run_sys -e "SELECT svr_ip, zone, cpu_capacity, cpu_max_assigned, mem_capacity, mem_max_assigned FROM GV\$OB_SERVERS ORDER BY zone;" 2>/dev/null || \
run_sys -e "SELECT * FROM GV\$OB_SERVERS\G" 2>/dev/null | head -80 || \
echo "(GV views not available)"
