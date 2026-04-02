#!/usr/bin/env bash
set -euo pipefail
LOG=/tmp/run_oceanbase_benchmark_nmysql_pp_20260402T093531Z.log
CSV=/tmp/oceanbase-bench/20260402T093531Z_d8s_v5_centos_nmysql_pp.csv

echo "RUNNING_PIDS:"
pgrep -af "run_oceanbase_benchmark_nmysql_pp.sh d8s_v5_centos_nmysql_pp" || echo "none"

echo "---TAIL LOG---"
tail -n 60 "$LOG" || true

echo "---CSV_LINES---"
wc -l "$CSV" 2>/dev/null || true

echo "---CSV_TAIL---"
tail -n 20 "$CSV" 2>/dev/null || true