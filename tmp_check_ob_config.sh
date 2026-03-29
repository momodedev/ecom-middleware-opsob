#!/bin/bash
set -uo pipefail

OB_PASS='OceanBase#!123'

run_sys() {
  mysql -h 10.100.1.6 -P 2881 -uroot@sys -p"$OB_PASS" -Doceanbase "$@"
}
run_tenant() {
  mysql -h 10.100.1.6 -P 2881 -uroot@sbtest_tenant -p"$OB_PASS" "$@"
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
echo "===== 4. UNIT CONFIGS ====="
run_sys -e "SELECT unit_config_id, name, max_cpu, min_cpu, max_memory, min_memory, max_iops, min_iops, max_disk_size, max_session_num FROM __all_unit_config;"

echo ""
echo "===== 5. TENANT UNITS PLACEMENT ====="
run_sys -e "SELECT t.tenant_name, u.svr_ip, u.zone, u.unit_id, u.resource_pool_id FROM __all_unit u JOIN __all_resource_pool p ON u.resource_pool_id = p.resource_pool_id JOIN __all_tenant t ON t.tenant_id = p.tenant_id ORDER BY t.tenant_name, u.zone;"

echo ""
echo "===== 6. SBTEST_TENANT VARIABLES ====="
for v in ob_query_timeout ob_trx_timeout ob_trx_idle_timeout max_connections ob_plan_cache_percentage parallel_servers_target ob_sql_work_area_percentage; do
  run_tenant -N -e "SHOW VARIABLES LIKE '$v';"
done

echo ""
echo "===== 7. CLUSTER-LEVEL PARAMETERS ====="
for p in memory_limit memory_limit_percentage system_memory cpu_count datafile_size datafile_disk_percentage log_disk_size log_disk_percentage enable_syslog_recycle max_syslog_file_count syslog_level minor_freeze_times merge_thread_count net_thread_count writing_throttling_trigger_percentage enable_sql_audit; do
  run_sys -N -e "SHOW PARAMETERS LIKE '$p';" 2>/dev/null | awk '{print $1, $2, $3, $4, $5, $6}'
done

echo ""
echo "===== 8. OBSERVER RESOURCE STATS ====="
run_sys -e "SELECT svr_ip, zone, cpu_capacity, cpu_assigned, mem_capacity, mem_assigned FROM __all_virtual_server_stat ORDER BY zone;" 2>/dev/null || echo "(not available)"

echo ""
echo "===== 9. DISK USAGE ====="
run_sys -e "SELECT svr_ip, zone, data_disk_capacity, data_disk_in_use, log_disk_capacity, log_disk_assigned, log_disk_in_use FROM __all_virtual_server_stat ORDER BY zone;" 2>/dev/null || echo "(not available)"

echo ""
echo "===== 10. OCEANBASE VERSION ====="
run_tenant -N -e "SELECT version();"

echo ""
echo "===== 11. SBTEST DATASET ====="
run_tenant -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='sbtest';"
run_tenant -N -e "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema='sbtest' ORDER BY table_name;"
