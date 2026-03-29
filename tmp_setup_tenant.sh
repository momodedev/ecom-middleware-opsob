#!/bin/bash
set -uo pipefail

HOST=10.100.1.6
PORT=2881
PASS='OceanBase#!123'

run_sys() {
  mysql -h "$HOST" -P "$PORT" -uroot@sys -p"$PASS" -Doceanbase "$@"
}

run_tenant() {
  mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -p"$PASS" "$@"
}

echo "===== 1. CREATE RESOURCE UNIT (max_cpu=6, memory=24G) ====="
run_sys -e "CREATE RESOURCE UNIT IF NOT EXISTS sbtest_unit MAX_CPU=6, MIN_CPU=6, MEMORY_SIZE='24G', LOG_DISK_SIZE='180G';"
echo "RC=$?"

echo ""
echo "===== 2. CREATE RESOURCE POOL ====="
run_sys -e "CREATE RESOURCE POOL IF NOT EXISTS sbtest_pool UNIT='sbtest_unit', UNIT_NUM=1, ZONE_LIST=('zone1','zone2','zone3');"
echo "RC=$?"

echo ""
echo "===== 3. CREATE TENANT ====="
run_sys -e "CREATE TENANT IF NOT EXISTS sbtest_tenant RESOURCE_POOL_LIST=('sbtest_pool'), PRIMARY_ZONE='RANDOM', LOCALITY=\"FULL{1}@zone1, FULL{1}@zone2, FULL{1}@zone3\" SET ob_tcp_invited_nodes='%';"
echo "RC=$?"

echo ""
echo "===== 4. SET ROOT PASSWORD ====="
# New tenant has empty root password, set it
mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -Doceanbase -e "ALTER USER root IDENTIFIED BY '$PASS';" 2>/dev/null
echo "RC=$?"

echo ""
echo "===== 5. WAIT FOR TENANT READY ====="
for i in $(seq 1 30); do
  if run_tenant -e "SELECT 1 AS ok;" >/dev/null 2>&1; then
    echo "Tenant ready after ${i} attempts"
    break
  fi
  echo "Waiting... attempt $i"
  sleep 3
done

echo ""
echo "===== 6. SET TENANT VARIABLES ====="
# ob_trx_timeout = 100ms = 100000 microseconds
run_tenant -e "SET GLOBAL ob_trx_timeout = 100000;"
echo "ob_trx_timeout RC=$?"

# ob_trx_lock_timeout = 1s = 1000000 microseconds
run_tenant -e "SET GLOBAL ob_trx_lock_timeout = 1000000;"
echo "ob_trx_lock_timeout RC=$?"

echo ""
echo "===== 7. SET CLUSTER PARAMETERS ====="
# cpu_quota_concurrency = 8
run_sys -e "ALTER SYSTEM SET cpu_quota_concurrency = 8;"
echo "cpu_quota_concurrency RC=$?"

# ob_fine_grained_lock = TRUE  (hidden parameter needs special syntax in some versions)
run_sys -e "ALTER SYSTEM SET _ob_fine_grained_lock = TRUE;" 2>/dev/null
rc1=$?
if [ $rc1 -ne 0 ]; then
  run_sys -e "ALTER SYSTEM SET ob_fine_grained_lock = TRUE;" 2>/dev/null
  rc1=$?
fi
echo "ob_fine_grained_lock RC=$rc1"

# elr_for_oltp = ON  (hidden parameter)
run_sys -e "ALTER SYSTEM SET _elr_for_oltp = ON;" 2>/dev/null
rc2=$?
if [ $rc2 -ne 0 ]; then
  run_sys -e "ALTER SYSTEM SET elr_for_oltp = ON;" 2>/dev/null
  rc2=$?
fi
echo "elr_for_oltp RC=$rc2"

echo ""
echo "===== 8. VERIFY TENANT EXISTS ====="
run_sys -e "SELECT tenant_id, tenant_name, zone_list, primary_zone, locality FROM __all_tenant;"

echo ""
echo "===== 9. VERIFY UNIT CONFIG ====="
run_sys -e "SELECT * FROM __all_unit_config WHERE name='sbtest_unit'\G"

echo ""
echo "===== 10. VERIFY RESOURCE POOL ====="
run_sys -e "SELECT name, unit_count, unit_config_id, zone_list, tenant_id FROM __all_resource_pool;"

echo ""
echo "===== 11. VERIFY TENANT VARIABLES ====="
run_tenant -e "SHOW GLOBAL VARIABLES LIKE 'ob_trx_timeout';"
run_tenant -e "SHOW GLOBAL VARIABLES LIKE 'ob_trx_lock_timeout';"

echo ""
echo "===== 12. VERIFY CLUSTER PARAMETERS ====="
run_sys -e "SHOW PARAMETERS LIKE 'cpu_quota_concurrency'\G" | grep -E "name|value"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE '%fine_grained_lock%'\G" | grep -E "name|value"
echo "---"
run_sys -e "SHOW PARAMETERS LIKE '%elr_for_oltp%'\G" | grep -E "name|value"

echo ""
echo "===== 13. VERIFY GV RESOURCES ====="
run_sys -e "SELECT svr_ip, zone, cpu_capacity, cpu_max_assigned, mem_capacity, mem_max_assigned FROM GV\$OB_SERVERS ORDER BY zone;" 2>/dev/null || \
run_sys -e "SELECT svr_ip, zone, CPU_CAPACITY, CPU_ASSIGNED, MEM_CAPACITY, MEM_ASSIGNED FROM GV\$OB_SERVERS ORDER BY zone;" 2>/dev/null

echo ""
echo "===== DONE ====="
