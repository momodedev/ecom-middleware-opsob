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

echo "===== 1. ADJUST MEMORY LIMITS ====="
echo "Current: memory_limit=26G, system_memory=4G => capacity=22G (only 21G free after sys 1G)"
echo "Target:  memory_limit=28G, system_memory=3G => capacity=25G (24G free after sys 1G)"

run_sys -e "ALTER SYSTEM SET memory_limit = '28G';"
echo "memory_limit RC=$?"

run_sys -e "ALTER SYSTEM SET system_memory = '3G';"
echo "system_memory RC=$?"

sleep 3
echo "Verify new capacity:"
run_sys -e "SELECT svr_ip, zone, CPU_CAPACITY, CPU_ASSIGNED, MEM_CAPACITY, MEM_ASSIGNED FROM GV\$OB_SERVERS ORDER BY zone;" 2>/dev/null

echo ""
echo "===== 2. DROP OLD UNIT IF WRONG CONFIG ====="
# Drop the unit created earlier (it may exist without a pool)
run_sys -e "DROP RESOURCE UNIT IF EXISTS sbtest_unit;" 2>/dev/null
echo "drop unit RC=$?"

echo ""
echo "===== 3. CREATE RESOURCE UNIT (max_cpu=6, memory=24G) ====="
run_sys -e "CREATE RESOURCE UNIT IF NOT EXISTS sbtest_unit MAX_CPU=6, MIN_CPU=6, MEMORY_SIZE='24G', LOG_DISK_SIZE='180G';"
echo "RC=$?"

echo ""
echo "===== 4. CREATE RESOURCE POOL ====="
run_sys -e "CREATE RESOURCE POOL IF NOT EXISTS sbtest_pool UNIT='sbtest_unit', UNIT_NUM=1, ZONE_LIST=('zone1','zone2','zone3');"
echo "RC=$?"

echo ""
echo "===== 5. CREATE TENANT ====="
run_sys -e "CREATE TENANT IF NOT EXISTS sbtest_tenant RESOURCE_POOL_LIST=('sbtest_pool'), PRIMARY_ZONE='RANDOM', LOCALITY=\"FULL{1}@zone1, FULL{1}@zone2, FULL{1}@zone3\" SET ob_tcp_invited_nodes='%';"
echo "RC=$?"

echo ""
echo "===== 6. SET ROOT PASSWORD (empty password first, then set) ====="
sleep 5
mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -Doceanbase -e "ALTER USER root IDENTIFIED BY '$PASS';" 2>/dev/null
echo "set password RC=$?"

echo ""
echo "===== 7. WAIT FOR TENANT READY ====="
for i in $(seq 1 30); do
  if run_tenant -e "SELECT 1 AS ok;" >/dev/null 2>&1; then
    echo "Tenant ready after ${i} attempts"
    break
  fi
  echo "Waiting... attempt $i"
  sleep 3
done

echo ""
echo "===== 8. SET TENANT VARIABLES ====="
# ob_trx_timeout = 100ms = 100000 microseconds
run_tenant -e "SET GLOBAL ob_trx_timeout = 100000;"
echo "ob_trx_timeout RC=$?"

# ob_trx_lock_timeout = 1s = 1000000 microseconds
run_tenant -e "SET GLOBAL ob_trx_lock_timeout = 1000000;"
echo "ob_trx_lock_timeout RC=$?"

echo ""
echo "===== 9. SET CLUSTER PARAMETERS ====="
# cpu_quota_concurrency = 8  (already set from previous run, verify)
run_sys -e "ALTER SYSTEM SET cpu_quota_concurrency = 8;"
echo "cpu_quota_concurrency RC=$?"

echo ""
echo "===== 10. SET HIDDEN PARAMETERS ====="
# Try various name formats for hidden params
echo "--- ob_fine_grained_lock ---"
run_sys -e "ALTER SYSTEM SET _ob_fine_grained_lock = true;" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "Trying without underscore prefix..."
  run_sys -e "ALTER SYSTEM SET ob_fine_grained_lock = true;" 2>&1
  rc=$?
fi
if [ $rc -ne 0 ]; then
  echo "Trying tenant scope..."
  run_tenant -e "SET GLOBAL _ob_fine_grained_lock = true;" 2>&1 || \
  run_tenant -e "SET GLOBAL ob_fine_grained_lock = true;" 2>&1
fi
echo "ob_fine_grained_lock final RC=$?"

echo "--- elr_for_oltp ---"
run_sys -e "ALTER SYSTEM SET _elr_for_oltp = true;" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "Trying without underscore prefix..."
  run_sys -e "ALTER SYSTEM SET elr_for_oltp = true;" 2>&1
  rc=$?
fi
if [ $rc -ne 0 ]; then
  echo "Trying tenant scope..."
  run_tenant -e "SET GLOBAL _elr_for_oltp = true;" 2>&1 || \
  run_tenant -e "SET GLOBAL elr_for_oltp = true;" 2>&1
fi
echo "elr_for_oltp final RC=$?"

echo ""
echo "===== 11. VERIFY ALL ====="
echo "--- Tenants ---"
run_sys -e "SELECT tenant_id, tenant_name, zone_list, primary_zone, locality FROM __all_tenant;"

echo "--- Unit Config ---"
run_sys -e "SELECT * FROM __all_unit_config WHERE name='sbtest_unit'\G"

echo "--- Resource Pool ---"
run_sys -e "SELECT name, unit_count, unit_config_id, zone_list, tenant_id FROM __all_resource_pool;"

echo "--- Tenant Variables ---"
run_tenant -e "SHOW GLOBAL VARIABLES LIKE 'ob_trx_timeout';"
run_tenant -e "SHOW GLOBAL VARIABLES LIKE 'ob_trx_lock_timeout';"

echo "--- Cluster Parameters ---"
run_sys -e "SHOW PARAMETERS LIKE 'cpu_quota_concurrency'\G" | grep -E "name|value" | head -4
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'memory_limit'\G" | grep -E "name|value" | head -4
echo "---"
run_sys -e "SHOW PARAMETERS LIKE 'system_memory'\G" | grep -E "name|value" | head -4
echo "---"
run_sys -e "SHOW PARAMETERS LIKE '%fine_grained%'\G" | grep -E "name|value" | head -4
echo "---"
run_sys -e "SHOW PARAMETERS LIKE '%elr%'\G" | grep -E "name|value" | head -4

echo "--- GV Resources ---"
run_sys -e "SELECT svr_ip, zone, CPU_CAPACITY, CPU_ASSIGNED, MEM_CAPACITY, MEM_ASSIGNED FROM GV\$OB_SERVERS ORDER BY zone;" 2>/dev/null

echo ""
echo "===== DONE ====="
