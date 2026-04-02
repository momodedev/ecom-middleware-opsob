#!/bin/bash
###############################################################################
# run_oceanbase_benchmark_nmysql_pp.sh
#
# CentOS OceanBase benchmark via OBProxy, aligned with nmysql_p test profile:
#   - 90 tables x 500,000 rows (~10 GB+)
#   - 300s per test case
#   - 120s warmup (50 threads, read_only)
#   - Workloads: oltp_read_only, oltp_write_only, oltp_read_write
#   - Thread ladder: 20, 50, 100, 200
#
# Usage:
#   ./run_oceanbase_benchmark_nmysql_pp.sh <cluster_label> <mysql_host> \
#       <mysql_user> <mysql_password> <mysql_db> [observer_ips] [obproxy_port]
#
# Example (CentOS control-node-co local OBProxy):
#   ./run_oceanbase_benchmark_nmysql_pp.sh d8s_v5_centos_nmysql_pp 127.0.0.1 \
#       root@sbtest_tenant 'OceanBase#!123' sbtest \
#       "10.100.1.4 10.100.1.5 10.100.1.6" 2883
###############################################################################
set -uo pipefail

if [ "$#" -lt 5 ]; then
  echo "Usage: $0 <cluster_label> <mysql_host> <mysql_user> <mysql_password> <mysql_db> [observer_ips] [obproxy_port]"
  exit 1
fi

RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
CLUSTER_LABEL="${RUN_TS}_$1"
MYSQL_HOST="$2"
MYSQL_USER="$3"
MYSQL_PASSWORD="$4"
MYSQL_DB="$5"
OBSERVER_IPS="${6:-10.100.1.4 10.100.1.5 10.100.1.6}"
MYSQL_PORT="${7:-2883}"

TABLE_SIZE="${TABLE_SIZE:-500000}"
TABLES="${TABLES:-90}"
RUN_TIME="${RUN_TIME:-300}"
WARMUP_TIME="${WARMUP_TIME:-120}"
WARMUP_THREADS="${WARMUP_THREADS:-50}"
PREPARE_THREADS="${PREPARE_THREADS:-50}"
REPORT_INTERVAL="${REPORT_INTERVAL:-5}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-30}"

THREADS_LIST="${THREADS_LIST:-20 50 100 200}"
WORKLOADS="${WORKLOADS:-oltp_read_only oltp_write_only oltp_read_write}"
SKIP_PREPARE="${SKIP_PREPARE:-0}"
SKIP_WARMUP="${SKIP_WARMUP:-0}"

OUTPUT_DIR="/tmp/oceanbase-bench"
CSV_FILE="${OUTPUT_DIR}/${CLUSTER_LABEL}.csv"
DEBUG_DIR="${OUTPUT_DIR}/${CLUSTER_LABEL}_debug"
mkdir -p "$OUTPUT_DIR" "$DEBUG_DIR"

SSH_KEY="${SSH_KEY:-/home/azureadmin/.ssh/id_rsa}"
SSH_USER="${SSH_USER:-oceanadmin}"

SYSBENCH_BASE="sysbench --db-driver=mysql \
  --mysql-host=${MYSQL_HOST} \
  --mysql-port=${MYSQL_PORT} \
  --mysql-user=${MYSQL_USER} \
  --mysql-password=${MYSQL_PASSWORD} \
  --mysql-db=${MYSQL_DB} \
  --tables=${TABLES} \
  --table-size=${TABLE_SIZE} \
  --events=0 \
  --report-interval=${REPORT_INTERVAL} \
  --db-ps-mode=disable \
  --mysql-ignore-errors=4012,6002,6210,4000,1213,1205"

collect_pre_metrics() {
  local snap_dir="$1"
  for mip in $OBSERVER_IPS; do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
      -i "$SSH_KEY" "${SSH_USER}@${mip}" \
      "head -1 /proc/stat; echo ===SEP===; cat /proc/diskstats" \
      2>/dev/null > "${snap_dir}/before_${mip}" || true
  done
}

collect_post_metrics() {
  local snap_dir="$1"
  for mip in $OBSERVER_IPS; do
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
      -i "$SSH_KEY" "${SSH_USER}@${mip}" \
      "head -1 /proc/stat; echo ===SEP===; cat /proc/diskstats; echo ===SEP===; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo" \
      2>/dev/null > "${snap_dir}/after_${mip}" || true
  done
}

compute_metrics() {
  local snap_dir="$1"
  local duration="$2"
  local cpu_sum=0 mem_sum=0 disk_sum=0 obs_count=0

  for mip in $OBSERVER_IPS; do
    local bf="${snap_dir}/before_${mip}"
    local af="${snap_dir}/after_${mip}"
    [ -s "$bf" ] && [ -s "$af" ] || continue
    obs_count=$((obs_count + 1))

    local cpu_b cpu_a c m d
    cpu_b=$(head -1 "$bf")
    cpu_a=$(head -1 "$af")
    c=$(printf '%s\n%s\n' "$cpu_b" "$cpu_a" | awk '
      NR==1 { for(i=2;i<=NF;i++) tb+=$i; ib=$5 }
      NR==2 { for(i=2;i<=NF;i++) ta+=$i; ia=$5
        dt=ta-tb; di=ia-ib
        if(dt>0) printf "%.1f",100*(1-di/dt); else print "0.0"
      }')
    c=${c:-0.0}
    cpu_sum=$(awk "BEGIN{printf \"%.1f\",$cpu_sum+$c}")

    m=$(awk 'BEGIN{p=0} /===SEP===/{p++;next}
      p>=2 && /^MemTotal/{t=$2}
      p>=2 && /^MemAvailable/{a=$2}
      END{if(t>0) printf "%.1f",(t-a)/t*100; else print "0.0"}' "$af")
    m=${m:-0.0}
    mem_sum=$(awk "BEGIN{printf \"%.1f\",$mem_sum+$m}")

    local disk_b_data disk_a_data
    disk_b_data=$(awk 'BEGIN{p=0} /===SEP===/{p=1;next} p==1' "$bf")
    disk_a_data=$(awk 'BEGIN{p=0} /===SEP===/{p++;next} p==1' "$af")
    d=$(printf 'BEFORE\n%s\nAFTER\n%s\n' "$disk_b_data" "$disk_a_data" | awk -v dur="$duration" '
      /^BEFORE/ {ph="b";next} /^AFTER/ {ph="a";next}
      $3 ~ /^(sd[a-z]|nvme[0-9]+n[0-9]+)$/ {
        if(ph=="b"){br+=$6;bw+=$10} else{ar+=$6;aw+=$10}
      }
      END{delta=(ar-br)+(aw-bw); if(dur>0) printf "%.2f",delta*512/1024/1024/dur; else print "0.00"}')
    d=${d:-0.00}
    disk_sum=$(awk "BEGIN{printf \"%.2f\",$disk_sum+$d}")
  done

  if [ "$obs_count" -gt 0 ]; then
    METRIC_CPU=$(awk "BEGIN{printf \"%.1f\",$cpu_sum/$obs_count}")
    METRIC_MEM=$(awk "BEGIN{printf \"%.1f\",$mem_sum/$obs_count}")
    METRIC_DISK=$(awk "BEGIN{printf \"%.2f\",$disk_sum/$obs_count}")
  else
    METRIC_CPU="0.0"; METRIC_MEM="0.0"; METRIC_DISK="0.00"
  fi
}

parse_sysbench() {
  local result="$1"

  TPS=$(echo "$result" | awk -F'[()]' '/transactions:/ {gsub(/ per sec\./, "", $2); print $2}' | awk '{print $1}' | tail -1)
  P95=$(echo "$result" | awk '/95th percentile:/ {print $3}' | tail -1)
  AVG_LAT=$(echo "$result" | awk '/avg:/ {print $2}' | tail -1)
  TOTAL_Q=$(echo "$result" | awk '/^[[:space:]]*queries:[[:space:]]+[0-9]+/ {print $2}' | tail -1)
  if [ -z "${TOTAL_Q:-}" ]; then
    TOTAL_Q=$(echo "$result" | awk '/^[[:space:]]*total:[[:space:]]+[0-9]+/ {print $2}' | tail -1)
  fi
  TOTAL_Q=$(echo "${TOTAL_Q:-0}" | tr -d ',')
  ERRS=$(echo "$result" | awk -F': ' '/ignored errors:/ {print $2}' | awk '{print $1}' | tail -1)

  TPS=${TPS:-0}
  P95=${P95:-0}
  AVG_LAT=${AVG_LAT:-0}
  TOTAL_Q=${TOTAL_Q:-0}
  ERRS=${ERRS:-0}
}

echo "=========================================="
echo " OceanBase Benchmark (CentOS via OBProxy)"
echo " Cluster:   ${CLUSTER_LABEL}"
echo " Host:      ${MYSQL_HOST}:${MYSQL_PORT}"
echo " User:      ${MYSQL_USER}"
echo " Tables:    ${TABLES} x ${TABLE_SIZE} rows"
echo " Run:       ${RUN_TIME}s per case"
echo " Warmup:    ${WARMUP_TIME}s (${WARMUP_THREADS} threads)"
echo " Threads:   ${THREADS_LIST}"
echo " Workloads: ${WORKLOADS}"
echo " CSV:       ${CSV_FILE}"
echo " Debug dir: ${DEBUG_DIR}"
echo "=========================================="

if ! mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
  echo "ERROR: Cannot connect through OBProxy: ${MYSQL_HOST}:${MYSQL_PORT} user=${MYSQL_USER}" >&2
  exit 2
fi

echo "[0/4] Ensuring database '${MYSQL_DB}' exists..."
mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
  -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DB};" 2>/dev/null || true

if [ "$SKIP_PREPARE" = "1" ]; then
  echo "[1/4] Skipping data prepare (SKIP_PREPARE=1)."
else
  echo "[1/4] Preparing test data (${TABLES} tables x ${TABLE_SIZE} rows)..."
  echo "      Cleaning up any existing tables first..."
  $SYSBENCH_BASE --threads="$PREPARE_THREADS" oltp_read_only cleanup >/dev/null 2>&1 || true

  echo "      Inserting data with ${PREPARE_THREADS} threads..."
  $SYSBENCH_BASE --threads="$PREPARE_THREADS" oltp_read_only prepare
  if [ $? -ne 0 ]; then
    echo "ERROR: Data preparation failed!" >&2
    exit 1
  fi
  echo "      Data preparation complete."
fi

if [ "$SKIP_WARMUP" = "1" ]; then
  echo "[2/4] Skipping warmup (SKIP_WARMUP=1)."
else
  echo "[2/4] Running warmup (${WARMUP_THREADS} threads, ${WARMUP_TIME}s, discarded)..."
  $SYSBENCH_BASE --threads="$WARMUP_THREADS" --time="$WARMUP_TIME" oltp_read_only run >/dev/null 2>&1 || true
  echo "      Warmup complete."
fi

echo "timestamp,cluster_label,workload,threads,tps,p95_ms,avg_latency_ms,total_queries,errors,exit_code,status,cpu_usage_pct,memory_usage_pct,disk_io_mbps" > "$CSV_FILE"

for workload in $WORKLOADS; do
  case "$workload" in
    oltp_read_only)  echo "[3/4] Running Read-Only gradient stress test..." ;;
    oltp_write_only) echo "[4/4] Running Write-Only gradient stress test..." ;;
    *)               echo "[4/4] Running Read-Write gradient stress test..." ;;
  esac

  for threads in $THREADS_LIST; do
    echo "  -> ${workload} threads=${threads} (${RUN_TIME}s)..."
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    snap_dir=$(mktemp -d)
    collect_pre_metrics "$snap_dir"

    result_file=$(mktemp)
    $SYSBENCH_BASE --threads="$threads" --time="$RUN_TIME" "$workload" run >"$result_file" 2>&1
    rc=$?

    result="$(cat "$result_file")"

    collect_post_metrics "$snap_dir"
    compute_metrics "$snap_dir" "$RUN_TIME"
    rm -rf "$snap_dir"

    parse_sysbench "$result"

    status="ok"
    if [ "$rc" -ne 0 ]; then
      status="failed"
      echo "     FAILED (rc=$rc)" >&2
    else
      echo "     OK: TPS=$TPS P95=${P95}ms"
    fi

    if [ "$rc" -ne 0 ] || [ "$TPS" = "0" ]; then
      dbg_file="${DEBUG_DIR}/${workload}_t${threads}_$(date +%Y%m%d_%H%M%S).log"
      cp "$result_file" "$dbg_file"
      echo "     Debug log saved: $dbg_file"
    fi

    rm -f "$result_file"

    echo "${now},${CLUSTER_LABEL},${workload},${threads},${TPS},${P95},${AVG_LAT},${TOTAL_Q},${ERRS},${rc},${status},${METRIC_CPU},${METRIC_MEM},${METRIC_DISK}" >> "$CSV_FILE"

    echo "     Sleeping ${SLEEP_BETWEEN}s..."
    sleep "$SLEEP_BETWEEN"
  done
done

echo "=========================================="
echo " Benchmark complete!"
echo " CSV: ${CSV_FILE}"
echo " Debug dir: ${DEBUG_DIR}"
echo "=========================================="
cat "$CSV_FILE"
