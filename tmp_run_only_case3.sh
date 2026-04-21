#!/usr/bin/env bash
set -Eeuo pipefail

HOST="13.83.163.165"
PORT="2881"
USER="root@sys"
PASS="OceanBase#!123"
DB="sbtest"
LABEL="tuned_case3_runonly_20260417"
OUTDIR="/tmp/oceanbase-bench"
CSV="${OUTDIR}/${LABEL}.csv"
LOG="${OUTDIR}/${LABEL}.log"
THREADS_LIST="20 50 100 200"
WORKLOADS="oltp_read_only oltp_read_write"
RUN_TIME=300
WARMUP_TIME=120
SLEEP_BETWEEN=30

mkdir -p "$OUTDIR"
: > "$LOG"

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }

log "=========================================="
log "OceanBase Benchmark (run-only, no-prepare)"
log "Host: ${HOST}:${PORT}"
log "DB: ${DB}"
log "Label: ${LABEL}"
log "CSV: ${CSV}"
log "LOG: ${LOG}"
log "=========================================="

echo "timestamp,cluster_label,workload,threads,tps,p95_ms,avg_latency_ms,total_queries,errors,exit_code,status,cpu_usage_pct,memory_usage_pct,disk_io_mbps" > "$CSV"

base=(
  sysbench
  --db-driver=mysql
  --mysql-host="${HOST}"
  --mysql-port="${PORT}"
  --mysql-user="${USER}"
  --mysql-password="${PASS}"
  --mysql-db="${DB}"
  --tables=90
  --table-size=500000
  --events=0
  --report-interval=5
  --db-ps-mode=disable
)

log "Warmup ${WARMUP_TIME}s @50 threads (read_only)"
"${base[@]}" --threads=50 --time="${WARMUP_TIME}" oltp_read_only run >/dev/null 2>&1 || true

for workload in ${WORKLOADS}; do
  log "Running workload=${workload}"
  for threads in ${THREADS_LIST}; do
    now="$(ts)"
    log "Case workload=${workload}, threads=${threads}, duration=${RUN_TIME}s"
    set +e
    out="$("${base[@]}" --threads="${threads}" --time="${RUN_TIME}" "${workload}" run 2>&1)"
    rc=$?
    set -e
    echo "$out" >> "$LOG"

    if [ "$rc" -eq 0 ]; then
      tps=$(echo "$out" | awk -F'[()]' '/transactions:/ {gsub(/ per sec\./, "", $2); print $2}' | awk '{print $1}' | tail -1)
      p95=$(echo "$out" | awk '/95th percentile:/ {print $3}' | tail -1)
      avg=$(echo "$out" | awk '/avg:/ {print $2}' | tail -1)
      q=$(echo "$out" | awk '/^[[:space:]]*queries:[[:space:]]+[0-9]+/ {print $2}' | tail -1)
      [ -z "$q" ] && q=$(echo "$out" | awk '/^[[:space:]]*total:[[:space:]]+[0-9]+/ {print $2}' | tail -1)
      q=$(echo "${q:-0}" | tr -d ',')
      e=$(echo "$out" | awk -F': ' '/ignored errors:/ {print $2}' | awk '{print $1}' | tail -1)
      tps=${tps:-0}; p95=${p95:-0}; avg=${avg:-0}; q=${q:-0}; e=${e:-0}
      echo "${now},${LABEL},${workload},${threads},${tps},${p95},${avg},${q},${e},0,ok,0.0,0.0,0.00" >> "$CSV"
      log "OK: TPS=${tps}, P95=${p95}ms, Avg=${avg}ms"
    else
      echo "${now},${LABEL},${workload},${threads},0,0,0,0,0,${rc},failed,0.0,0.0,0.00" >> "$CSV"
      log "FAILED: rc=${rc}"
    fi

    log "Cooling down ${SLEEP_BETWEEN}s"
    sleep "${SLEEP_BETWEEN}"
  done
done

log "Benchmark complete"
log "CSV: ${CSV}"
