#!/usr/bin/env bash
set -euo pipefail

HOST=172.17.1.7
PORT=2883
USER='root@sbtest_tenant#ob_cluster'
PASS='OceanBase#!123'
DB=sbtest
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUTDIR=/tmp/oceanbase-bench/post_restart_${TS}
mkdir -p "$OUTDIR"

echo "=== SMOKE QUERY ==="
mysql -h"$HOST" -P"$PORT" -u"$USER" -p"$PASS" -D"$DB" -Nse "SELECT NOW() AS now_utc, @@version_comment AS version_comment;"
mysql -h"$HOST" -P"$PORT" -u"$USER" -p"$PASS" -D"$DB" -Nse "SELECT COUNT(*) AS sbtest1_rows FROM sbtest1;"
mysql -h"$HOST" -P"$PORT" -u"$USER" -p"$PASS" -D"$DB" -Nse "SELECT id,k FROM sbtest1 ORDER BY id LIMIT 3;"

run_case() {
  local mode="$1"
  local lua="$2"
  local out="$OUTDIR/${mode}_120s.out"
  echo "=== BENCH ${mode} (threads=100,time=120s) ==="
  sysbench "$lua" \
    --db-driver=mysql \
    --mysql-host="$HOST" \
    --mysql-port="$PORT" \
    --mysql-user="$USER" \
    --mysql-password="$PASS" \
    --mysql-db="$DB" \
    --tables=10 \
    --table-size=100000 \
    --threads=100 \
    --time=120 \
    --report-interval=20 \
    run > "$out"
  awk -v m="$mode" '/transactions:/{tps=$3} /95th percentile:/{p95=$3} END{printf("SUMMARY %s TPS=%s P95ms=%s\n",m,tps,p95)}' "$out"
}

run_case "read_only" "/usr/share/sysbench/oltp_read_only.lua"
run_case "write_only" "/usr/share/sysbench/oltp_write_only.lua"
run_case "read_write" "/usr/share/sysbench/oltp_read_write.lua"

echo "=== OUTPUT DIR ==="
echo "$OUTDIR"