#!/bin/bash
# OceanBase Standalone v4.5.0 - Full Configuration Check

OB="obclient -h127.0.0.1 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -A"

echo "============================================================"
echo "=== OceanBase Standalone v4.5.0 Configuration Check ==="
echo "============================================================"
echo ""

echo "--- Version ---"
eval $OB -e "SELECT @@version, @@version_comment;"

echo ""
echo "--- Cluster Info ---"
eval $OB -e "SELECT * FROM oceanbase.DBA_OB_CLUSTERS;" 2>/dev/null || \
eval $OB -e "SHOW PARAMETERS LIKE '%cluster_name%';"

echo ""
echo "--- Servers ---"
eval $OB -e "SELECT SVR_IP, SVR_PORT, ZONE, STATUS, START_SERVICE_TIME, STOP_TIME, BUILD_VERSION FROM oceanbase.DBA_OB_SERVERS;"

echo ""
echo "--- Zones ---"
eval $OB -e "SELECT * FROM oceanbase.DBA_OB_ZONES;"

echo ""
echo "--- Tenants ---"
eval $OB -e "SELECT TENANT_ID, TENANT_NAME, TENANT_TYPE, STATUS, MODE, LOCALITY, PRIMARY_ZONE, COMPATIBILITY_MODE FROM oceanbase.DBA_OB_TENANTS;"

echo ""
echo "--- Resource Units ---"
eval $OB -e "SELECT * FROM oceanbase.DBA_OB_UNIT_CONFIGS;"

echo ""
echo "--- Resource Pools ---"
eval $OB -e "SELECT * FROM oceanbase.DBA_OB_RESOURCE_POOLS;"

echo ""
echo "--- Units (placement) ---"
eval $OB -e "SELECT UNIT_ID, TENANT_ID, SVR_IP, SVR_PORT, ZONE, STATUS, MAX_CPU, MIN_CPU, MEMORY_SIZE, LOG_DISK_SIZE FROM oceanbase.GV$OB_UNITS;" 2>/dev/null || \
eval $OB -e "SELECT * FROM oceanbase.DBA_OB_UNITS;"

echo ""
echo "--- System Parameters (key configs) ---"
eval $OB -e "SHOW PARAMETERS WHERE name IN (
  'memory_limit','memory_limit_percentage','cpu_count',
  'datafile_size','datafile_maxsize','log_disk_size',
  'syslog_level','enable_syslog_recycle','max_syslog_file_count',
  'net_thread_count','server_permanent_offline_time',
  'minor_freeze_times','freeze_trigger_percentage',
  'enable_perf_event','system_memory',
  'cache_wash_threshold','tablet_size'
);"

echo ""
echo "--- All System Parameters ---"
eval $OB -e "SHOW PARAMETERS;" 2>&1 | head -200

echo ""
echo "--- OBD YAML Config ---"
cat /home/admin/ob-standalone.yaml 2>/dev/null || echo "(not found)"

echo ""
echo "--- OceanBase Data Directories ---"
ls -lah /oceanbase/data /oceanbase/redo 2>/dev/null || ls -lah /home/admin/oceanbase/store 2>/dev/null || echo "(dirs not found)"

echo ""
echo "--- Disk Usage ---"
df -h /oceanbase 2>/dev/null || df -h /home/admin 2>/dev/null

echo ""
echo "--- Memory Summary ---"
free -h

echo ""
echo "--- CPU ---"
nproc
lscpu | grep -E "Model name|CPU\(s\)|MHz"

echo ""
echo "--- OceanBase Process ---"
ps -ef | grep observer | grep -v grep
