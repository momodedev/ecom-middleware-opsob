#!/bin/bash
# express_oltp optimization for CentOS cluster (observers: 10.100.1.4/5/6)
# Run from control-node-co (20.14.74.130)
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

echo "=========================================="
echo " express_oltp Optimization - CentOS Cluster"
echo "=========================================="

echo ""
echo "===== 0. PRE-CHECK: parameter_template support ====="
run_sys -e "SHOW PARAMETERS LIKE 'parameter_template';" 2>&1 | head -5
# Try applying template directly first
run_sys -e "ALTER TENANT sbtest_tenant SET parameter_template='express_oltp';" 2>&1
echo "Template apply RC=$?"

echo ""
echo "===== 1. CLUSTER PARAMETERS (ALTER SYSTEM) ====="

# enable_sql_audit = false (reduce system overhead)
run_sys -e "ALTER SYSTEM SET enable_sql_audit = false;"
echo "enable_sql_audit=false RC=$?"

# writing_throttling_trigger_percentage = 75 (optimize write trigger threshold)
run_sys -e "ALTER SYSTEM SET writing_throttling_trigger_percentage = 75;"
echo "writing_throttling_trigger_percentage=75 RC=$?"

# cpu_quota_concurrency = 8 (increase active threads for high concurrency)
run_sys -e "ALTER SYSTEM SET cpu_quota_concurrency = 8;"
echo "cpu_quota_concurrency=8 RC=$?"

# minor_freeze_times / minor_compact_trigger (reduce Minor Merge frequency)
run_sys -e "ALTER SYSTEM SET minor_compact_trigger = 50;" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "minor_compact_trigger not found, trying minor_freeze_times..."
  run_sys -e "ALTER SYSTEM SET minor_freeze_times = 50;" 2>&1
  rc=$?
fi
echo "minor_freeze/compact=50 RC=$rc"

# Log transport compression
run_sys -e "ALTER SYSTEM SET log_transport_compress_all = true;" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "Trying alternate name..."
  run_sys -e "ALTER SYSTEM SET _log_transport_compress_all = true;" 2>&1
  rc=$?
fi
if [ $rc -ne 0 ]; then
  echo "Trying log_transport_compress_func..."
  run_sys -e "ALTER SYSTEM SET log_transport_compress_func = 'lz4_1.0';" 2>&1
  rc=$?
fi
echo "log_transport_compress RC=$rc"

echo ""
echo "===== 2. TENANT VARIABLES (sbtest_tenant) ====="

# ob_trx_timeout = 100ms = 100000 microseconds
run_tenant -e "SET GLOBAL ob_trx_timeout = 100000;"
echo "ob_trx_timeout=100000 RC=$?"

# ob_trx_lock_timeout = 1s = 1000000 microseconds
run_tenant -e "SET GLOBAL ob_trx_lock_timeout = 1000000;"
echo "ob_trx_lock_timeout=1000000 RC=$?"

echo ""
echo "===== 3. VERIFY CLUSTER PARAMETERS ====="
echo "--- enable_sql_audit ---"
run_sys -e "SHOW PARAMETERS LIKE 'enable_sql_audit'\G" | grep -E "name|value" | head -4
echo "--- writing_throttling_trigger_percentage ---"
run_sys -e "SHOW PARAMETERS LIKE 'writing_throttling_trigger_percentage'\G" | grep -E "name|value" | head -4
echo "--- cpu_quota_concurrency ---"
run_sys -e "SHOW PARAMETERS LIKE 'cpu_quota_concurrency'\G" | grep -E "name|value" | head -4
echo "--- minor_compact_trigger ---"
run_sys -e "SHOW PARAMETERS LIKE '%minor_compact%'\G" | grep -E "name|value" | head -4
run_sys -e "SHOW PARAMETERS LIKE '%minor_freeze%'\G" | grep -E "name|value" | head -4
echo "--- log_transport_compress ---"
run_sys -e "SHOW PARAMETERS LIKE '%log_transport%'\G" | grep -E "name|value" | head -4
echo "--- enable_early_lock_release ---"
run_sys -e "SHOW PARAMETERS LIKE 'enable_early_lock_release'\G" | grep -E "name|value" | head -4

echo ""
echo "===== 4. VERIFY TENANT VARIABLES ====="
run_tenant -e "SHOW GLOBAL VARIABLES LIKE 'ob_trx_timeout';"
run_tenant -e "SHOW GLOBAL VARIABLES LIKE 'ob_trx_lock_timeout';"

echo ""
echo "===== 5. RESOURCE SUMMARY ====="
run_sys -e "SELECT svr_ip, zone, CPU_CAPACITY, CPU_ASSIGNED, MEM_CAPACITY, MEM_ASSIGNED FROM GV\$OB_SERVERS ORDER BY zone;" 2>/dev/null
run_sys -e "SELECT tenant_id, tenant_name FROM __all_tenant;"

echo ""
echo "===== DONE - CentOS Cluster ====="
