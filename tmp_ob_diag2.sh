#!/bin/bash
set -uo pipefail

MYSQL="mysql -h172.17.1.7 -P2881 -uroot@sys -pOceanBase#!123 -Doceanbase -A"

echo "=== TENANT DETAILS ==="
$MYSQL -e "SELECT TENANT_ID, TENANT_NAME, TENANT_TYPE, PRIMARY_ZONE, LOCALITY, COMPATIBILITY_MODE FROM DBA_OB_TENANTS"

echo ""
echo "=== UNITS ==="
$MYSQL -e "SELECT UNIT_ID, TENANT_ID, SVR_IP, SVR_PORT, ZONE FROM DBA_OB_UNITS"

echo ""
echo "=== OB PARAMETERS (perf related) ==="
$MYSQL -e "SHOW PARAMETERS LIKE 'log_disk_size'"
$MYSQL -e "SHOW PARAMETERS LIKE 'datafile_size'"
$MYSQL -e "SHOW PARAMETERS LIKE 'workers_per_cpu_quota'"

echo ""
echo "=== BENCHMARK SPECIFIC: check if sysbench ran against sys tenant ==="
$MYSQL -e "SHOW DATABASES LIKE 'sbtest'"

echo ""
echo "=== OBSERVER LOG errors during benchmark time ==="
ssh -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 "grep -iE 'FATAL|ERROR|OOM|throttl|memstore.*full|out.of.memory|lock.conflict|timeout' /oceanbase/server/log/observer.log 2>/dev/null | tail -30"

echo ""
echo "=== PALF/CLOG DISK ==="
$MYSQL -e "SELECT SVR_IP, SVR_PORT, PALF_DISK_USAGE FROM GV\$OB_LOG_STAT LIMIT 3" 2>/dev/null || {
  ssh -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 "du -sh /oceanbase/data/clog/ /oceanbase/redo/ 2>/dev/null; df -h /oceanbase/data /oceanbase/redo"
}

echo ""
echo "=== NETWORK BANDWIDTH ==="
ssh -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 "cat /sys/class/net/eth0/speed 2>/dev/null; ethtool eth0 2>/dev/null | grep Speed"
