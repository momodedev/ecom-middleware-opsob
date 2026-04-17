#!/bin/bash
# OceanBase full config check - uses SQL file to avoid quoting issues

PASS='OceanBase#!123'
OB_CMD="obclient -h127.0.0.1 -P2881 -uroot@sys -p${PASS} -Doceanbase -A"

run_sql() {
    echo "$1" | $OB_CMD 2>&1
}

echo "============================================================"
echo "=== OceanBase Standalone v4.5.0 Configuration Check ==="
echo "============================================================"

echo ""
echo "--- Version ---"
run_sql "SELECT @@version, @@version_comment;"

echo ""
echo "--- Servers ---"
run_sql "SELECT SVR_IP, SVR_PORT, ZONE, STATUS, START_SERVICE_TIME, BUILD_VERSION FROM oceanbase.DBA_OB_SERVERS;"

echo ""
echo "--- Zones ---"
run_sql "SELECT ZONE, STATUS, REGION, IDC, ZONE_TYPE, STORAGE_TYPE FROM oceanbase.DBA_OB_ZONES;"

echo ""
echo "--- Tenants ---"
run_sql "SELECT TENANT_ID, TENANT_NAME, TENANT_TYPE, STATUS, MODE, LOCALITY, PRIMARY_ZONE, COMPATIBILITY_MODE FROM oceanbase.DBA_OB_TENANTS;"

echo ""
echo "--- Resource Unit Configs ---"
run_sql "SELECT NAME, MAX_CPU, MIN_CPU, MEMORY_SIZE, MAX_IOPS, MIN_IOPS, LOG_DISK_SIZE FROM oceanbase.DBA_OB_UNIT_CONFIGS;"

echo ""
echo "--- Resource Pools ---"
run_sql "SELECT RESOURCE_POOL_ID, NAME, TENANT_ID, UNIT_COUNT, UNIT_CONFIG_ID, ZONE_LIST FROM oceanbase.DBA_OB_RESOURCE_POOLS;"

echo ""
echo "--- Units (server placement) ---"
run_sql "SELECT UNIT_ID, TENANT_ID, SVR_IP, SVR_PORT, ZONE, STATUS, MAX_CPU, MIN_CPU, MEMORY_SIZE, LOG_DISK_SIZE FROM oceanbase.GV\$OB_UNITS;"

echo ""
echo "--- Key System Parameters ---"
run_sql "SELECT zone, name, value, description FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN ('memory_limit','memory_limit_percentage','cpu_count','datafile_size','datafile_maxsize','log_disk_size','system_memory','net_thread_count','server_permanent_offline_time','minor_freeze_times','freeze_trigger_percentage','enable_syslog_recycle','max_syslog_file_count','syslog_level','cache_wash_threshold','tablet_size','production_mode') ORDER BY name;"

echo ""
echo "--- All System Parameters (first 100) ---"
run_sql "SELECT zone, name, value, section FROM oceanbase.GV\$OB_PARAMETERS ORDER BY name LIMIT 100;"

echo ""
echo "--- All System Parameters (next 100) ---"
run_sql "SELECT zone, name, value, section FROM oceanbase.GV\$OB_PARAMETERS ORDER BY name LIMIT 100 OFFSET 100;"

echo ""
echo "--- All System Parameters (next 100) ---"
run_sql "SELECT zone, name, value, section FROM oceanbase.GV\$OB_PARAMETERS ORDER BY name LIMIT 100 OFFSET 200;"

echo ""
echo "--- All System Parameters (next 100) ---"
run_sql "SELECT zone, name, value, section FROM oceanbase.GV\$OB_PARAMETERS ORDER BY name LIMIT 100 OFFSET 300;"

echo ""
echo "--- OBD YAML Config ---"
cat /home/admin/ob-standalone.yaml 2>/dev/null || echo "(not found at /home/admin/ob-standalone.yaml)"
ls /home/admin/.obd/cluster/ob_standalone/ 2>/dev/null

echo ""
echo "--- Data & Redo Disk Usage ---"
df -h /oceanbase /oceanbase/data /oceanbase/redo 2>/dev/null || df -h /home/admin/oceanbase 2>/dev/null

echo ""
echo "--- Memory ---"
free -h

echo ""
echo "--- CPU ---"
nproc
lscpu | grep -E "Model name|^CPU\(s\)|Thread|Socket|MHz"

echo ""
echo "--- OceanBase Process Args ---"
ps -ef | grep observer | grep -v grep | head -2
