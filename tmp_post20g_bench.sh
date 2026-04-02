#!/usr/bin/env bash
set -euo pipefail
run_case() {
  local mode="$1"
  local lua="$2"
  local out="/tmp/${mode}_post_tenant20g.out"
  echo "=== BENCH ${mode} (threads=100,time=60s) ==="
  sysbench "$lua" \
    --db-driver=mysql \
    --mysql-host=172.17.1.7 \
    --mysql-port=2883 \
    --mysql-user='root@sbtest_tenant#ob_cluster' \
    --mysql-password='OceanBase#!123' \
    --mysql-db=sbtest \
    --tables=10 \
    --table-size=100000 \
    --threads=100 \
    --time=60 \
    --report-interval=10 \
    run | tee "$out"
  echo "--- ${mode} summary ---"
  awk '/transactions:/{tps=$3} /95th percentile:/{p95=$3} END{printf("TPS=%s P95ms=%s\n",tps,p95)}' "$out"
}
run_case "read_only" "/usr/share/sysbench/oltp_read_only.lua"
run_case "read_write" "/usr/share/sysbench/oltp_read_write.lua"