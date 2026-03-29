#!/bin/bash
PASS='OceanBase#!123'

echo "============================================"
echo " FINAL VERIFICATION - Rocky Cluster"
echo "============================================"

run_sys() {
  mysql -h 172.17.1.6 -P 2881 -uroot@sys -p"$PASS" -Doceanbase "$@"
}
run_tenant() {
  mysql -h 172.17.1.6 -P 2881 -u'root@sbtest_tenant' -p"$PASS" "$@"
}

echo ""
echo "=== CLUSTER PARAMS (from sys) ==="
for P in enable_sql_audit writing_throttling_trigger_percentage cpu_quota_concurrency enable_early_lock_release log_transport_compress_all; do
  V=$(run_sys -N -e "SHOW PARAMETERS LIKE '$P'\G" 2>/dev/null | grep "value:" | head -1 | awk -F': ' '{print $2}')
  printf "  %-45s = %s\n" "$P" "$V"
done

echo ""
echo "=== TENANT PARAMS (from sbtest_tenant) ==="
V=$(run_tenant -N -e "SHOW PARAMETERS LIKE 'minor_compact_trigger'\G" 2>/dev/null | grep "value:" | head -1 | awk -F': ' '{print $2}')
printf "  %-45s = %s\n" "minor_compact_trigger" "$V"

echo ""
echo "=== TENANT VARIABLES ==="
run_tenant -N -e "SHOW GLOBAL VARIABLES LIKE 'ob_trx_timeout';" 2>/dev/null
run_tenant -N -e "SHOW GLOBAL VARIABLES LIKE 'ob_trx_lock_timeout';" 2>/dev/null

echo ""
echo "=== RESOURCE ALLOCATION ==="
run_sys -e "SELECT svr_ip, zone, CPU_CAPACITY, CPU_ASSIGNED, MEM_CAPACITY, MEM_ASSIGNED FROM GV\$OB_SERVERS ORDER BY zone;" 2>/dev/null

echo ""
echo "=== UNIT CONFIG ==="
run_sys -N -e "SELECT name, max_cpu, min_cpu, memory_size, log_disk_size FROM __all_unit_config WHERE name='sbtest_unit';"
