#!/bin/bash
# Runs only oltp_write_only + oltp_read_write for both direct and OBProxy paths.
# Appends results to _rw_only CSVs; merge_rw_results.py then combines them with
# the existing read-only CSVs into the final comparison.
set -euo pipefail

OUTPUT_DIR="/tmp/oceanbase-bench"
mkdir -p "$OUTPUT_DIR"

THREADS=(16 32 64 128 256)
WORKLOADS=(oltp_write_only oltp_read_write)
TOTAL=$((${#WORKLOADS[@]} * ${#THREADS[@]}))

run_workloads() {
  local LABEL=$1
  local PORT=$2
  local USER=$3
  local OB_DIR_PORT=2881   # always connect to OB directly for admin commands
  local OUT_CSV="$OUTPUT_DIR/${LABEL}_rw.csv"

  echo ""
  echo "======================================================"
  echo "  Path: $LABEL  port=$PORT"
  echo "  Start: $(date)"
  echo "======================================================"

  # Set OB transaction timeouts at GLOBAL (tenant) scope before write workloads.
  # ob_trx_timeout may have been tuned to 100ms by the cluster optimizer; reset to
  # 100s so sysbench write transactions don't abort immediately.
  echo "  Setting ob_trx_timeout=100s for sbtest_tenant..."
  mysql -h 172.17.1.7 -P $OB_DIR_PORT -u "root@sbtest_tenant" -p'OceanBase#!123' \
    -e "SET GLOBAL ob_trx_timeout=100000000; SET GLOBAL ob_trx_lock_timeout=10000000;" 2>&1 \
    || echo "  WARNING: SET GLOBAL failed (may need sys-tenant access); proceeding anyway"

  cat > "$OUT_CSV" <<'HEADER'
timestamp,label,workload,threads,tps,p95_latency,avg_latency,total_queries,errors,rc,status,cpu_pct,mem_pct,disk_io_mbps
HEADER

  local TC=0
  for workload in "${WORKLOADS[@]}"; do
    for threads in "${THREADS[@]}"; do
      TC=$((TC + 1))
      echo "[$(date)] [$LABEL] Test $TC/$TOTAL: workload=$workload threads=$threads"

      NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      RESULT_FILE=$(mktemp)

      set +e
      sysbench /usr/share/sysbench/${workload}.lua \
        --db-driver=mysql \
        --mysql-host=172.17.1.7 \
        --mysql-port=$PORT \
        --mysql-user="$USER" \
        --mysql-password='OceanBase#!123' \
        --mysql-db=sbtest \
        --tables=10 \
        --table-size=100000 \
        --threads=$threads \
        --time=120 \
        --report-interval=10 \
        --db-ps-mode=disable \
        --mysql-ignore-errors=4012,6002,6210,4000,1213,1205 \
        run >"$RESULT_FILE" 2>&1
      RC=$?
      set -e

      RESULT=$(cat "$RESULT_FILE")

      TPS=$(echo "$RESULT" | awk -F'[()]' '/transactions:/{gsub(/ per sec\./, "", $2); print $2}' | awk '{print $1}' | tail -1); TPS=${TPS:-0}
      P95=$(echo "$RESULT" | awk '/95th percentile:/{print $3}' | tail -1); P95=${P95:-0}
      AVG=$(echo "$RESULT" | awk '/avg:/{print $2}' | tail -1); AVG=${AVG:-0}
      TQ=$(echo "$RESULT"  | awk '/^[[:space:]]*queries:[[:space:]]+[0-9]+/{print $2}' | tail -1); TQ=${TQ:-0}
      ERR=$(echo "$RESULT" | awk -F': ' '/ignored errors:/{print $2}' | awk '{print $1}' | tail -1); ERR=${ERR:-0}

      STATUS="ok"
      [ "$RC" -ne 0 ] && STATUS="failed"

      if [[ "$RC" -ne 0 || "$TPS" == "0" ]]; then
        DBG="$OUTPUT_DIR/debug_${LABEL}_${workload}_t${threads}.log"
        cp "$RESULT_FILE" "$DBG"
        echo "  => RC=$RC  TPS=$TPS  debug: $DBG"
        tail -6 "$DBG" | sed 's/^/     /'
      fi

      echo "$NOW,$LABEL,$workload,$threads,$TPS,$P95,$AVG,$TQ,$ERR,$RC,$STATUS,0.0,0.0,0.00" >> "$OUT_CSV"
      echo "  => TPS=$TPS P95=$P95 Status=$STATUS"
      rm -f "$RESULT_FILE"
    done
  done

  echo "  Done: $OUT_CSV"
}

# Direct path first, then proxy (sequential to avoid table contention)
run_workloads "d8s_v5_rocky_direct"  2881 "root@sbtest_tenant"
run_workloads "d8s_v5_rocky_obproxy" 2883 "root@sbtest_tenant#ob_cluster"

echo ""
echo "=== All write/RW benchmarks complete ==="
echo "Direct RW:  $OUTPUT_DIR/d8s_v5_rocky_direct_rw.csv"
echo "Proxy  RW:  $OUTPUT_DIR/d8s_v5_rocky_obproxy_rw.csv"
echo "End time: $(date)"
