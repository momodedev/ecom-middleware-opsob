#!/bin/bash
###############################################################################
# run_oceanbase_benchmark_nmysql.sh  (CentOS cluster variant)
#
# OceanBase sysbench benchmark script following Ruizhen Huang's test spec:
#   - 90 tables × 500,000 rows (~10 GB+)
#   - 300 s run time per test case
#   - 120 s buffer-pool warmup (50 threads, read_only, results discarded)
#   - Workloads: oltp_read_only, oltp_read_write
#   - Thread ladder: 20, 50, 100, 200
#   - 30 s cool-down sleep between cases
#
# Usage:
#   ./run_oceanbase_benchmark_nmysql.sh <cluster_label> <mysql_host> \
#       <mysql_user> <mysql_password> <mysql_db> [observer_ips]
#
# Example:
#   ./run_oceanbase_benchmark_nmysql.sh d8s_v5_centos 10.100.1.6 \
#       root@sbtest_tenant 'OceanBase#!123' sbtest "10.100.1.4 10.100.1.5 10.100.1.6"
###############################################################################
set -uo pipefail

if [ "$#" -lt 5 ]; then
  echo "Usage: $0 <cluster_label> <mysql_host> <mysql_user> <mysql_password> <mysql_db> [observer_ips]"
  exit 1
fi

RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
CLUSTER_LABEL="${RUN_TS}_$1"
MYSQL_HOST="$2"
MYSQL_USER="$3"
MYSQL_PASSWORD="$4"
MYSQL_DB="$5"
OBSERVER_IPS="${6:-$MYSQL_HOST}"
MYSQL_PORT=2881

TABLE_SIZE=500000
TABLES=90
RUN_TIME=300
WARMUP_TIME=120
WARMUP_THREADS=50
PREPARE_THREADS=50
REPORT_INTERVAL=5
SLEEP_BETWEEN=30

THREADS_LIST="20 50 100 200"
WORKLOADS="oltp_read_only oltp_read_write"

OUTPUT_DIR="/tmp/oceanbase-bench"
CSV_FILE="${OUTPUT_DIR}/${CLUSTER_LABEL}.csv"

SSH_KEY="${SSH_KEY:-/home/azureadmin/.ssh/id_rsa}"
SSH_USER="${SSH_USER:-oceanadmin}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://127.0.0.1:9090}"
PROM_TIMEOUT_SEC="${PROM_TIMEOUT_SEC:-8}"

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
  --db-ps-mode=disable"

mkdir -p "$OUTPUT_DIR"

###############################################################################
# Helper: collect system metrics from observer nodes
###############################################################################
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
        d=ta-tb; id=ia-ib
        if(d>0) printf "%.1f",100*(1-id/d); else print "0.0"
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
      END{delta=(ar-br)+(aw-bw); printf "%.2f",delta*512/1024/1024/dur}')
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

###############################################################################
# Helper: collect OceanBase dashboard metrics from Prometheus
###############################################################################
json_vector_avg() {
  local json="$1"
  local vals avg

  if command -v jq >/dev/null 2>&1; then
    vals=$(printf '%s' "$json" | jq -r '.data.result[].value[1]' 2>/dev/null || true)
  else
    vals=$(printf '%s' "$json" \
      | grep -o '"value":\[[^]]*\]' \
      | sed -E 's/.*,"([^"]+)"\]/\1/' || true)
  fi

  if [ -z "${vals:-}" ]; then
    echo "0"
    return
  fi

  avg=$(printf '%s\n' "$vals" | awk '{s+=$1; n+=1} END{if(n>0) printf "%.6f", s/n; else print "0"}')
  echo "${avg:-0}"
}

prom_query_avg() {
  local q="$1"
  local resp
  resp=$(curl -sS --max-time "$PROM_TIMEOUT_SEC" --get \
    --data-urlencode "query=${q}" \
    "${PROMETHEUS_URL}/api/v1/query" 2>/dev/null || true)

  if [ -z "${resp:-}" ] || ! printf '%s' "$resp" | grep -q '"status":"success"'; then
    echo "0"
    return
  fi

  json_vector_avg "$resp"
}

collect_prometheus_metrics() {
  # Host performance (Obshell -> Performance Monitoring -> OceanBase Cluster -> Host performance)
  PROM_HOST_LOAD1=$(prom_query_avg 'node_load1{app="HOST"}')
  PROM_HOST_CPU_PCT=$(prom_query_avg '100 * (1 - (sum(rate(node_cpu_seconds_total{app="HOST",mode="idle"}[1m])) / clamp_min(sum(rate(node_cpu_seconds_total{app="HOST"}[1m])), 1e-9)))')
  PROM_HOST_MEM_USED_BYTES=$(prom_query_avg 'node_memory_MemTotal_bytes{app="HOST"} - node_memory_MemAvailable_bytes{app="HOST"}')
  PROM_HOST_MEM_PCT=$(prom_query_avg '100 * (1 - (avg(node_memory_MemAvailable_bytes{app="HOST"}) / clamp_min(avg(node_memory_MemTotal_bytes{app="HOST"}), 1)))')
  PROM_HOST_IOPS=$(prom_query_avg 'rate(node_disk_reads_completed_total{app="HOST"}[1m]) + rate(node_disk_writes_completed_total{app="HOST"}[1m])')
  PROM_HOST_IO_TIME_US=$(prom_query_avg '1e6 * (rate(node_disk_read_time_seconds_total{app="HOST"}[1m]) + rate(node_disk_write_time_seconds_total{app="HOST"}[1m]))')
  PROM_HOST_IO_THROUGHPUT=$(prom_query_avg 'rate(node_disk_read_bytes_total{app="HOST"}[1m]) + rate(node_disk_written_bytes_total{app="HOST"}[1m])')
  PROM_HOST_NET_THROUGHPUT=$(prom_query_avg 'rate(node_network_receive_bytes_total{app="HOST"}[1m]) + rate(node_network_transmit_bytes_total{app="HOST"}[1m])')

  # OceanBase cluster database performance
  PROM_OB_SERVER_NUM=$(prom_query_avg 'ob_server_num')
  PROM_OB_ACTIVE_SESSIONS=$(prom_query_avg 'ob_active_session_num')
  PROM_OB_ALL_SESSIONS=$(prom_query_avg 'ob_all_session_num')
  PROM_OB_CPU_ASSIGNED_PCT=$(prom_query_avg 'ob_server_resource_cpu_assigned_percent')
  PROM_OB_MEM_ASSIGNED_PCT=$(prom_query_avg 'ob_server_resource_memory_assigned_percent')
  PROM_OB_DISK_TOTAL_BYTES=$(prom_query_avg 'ob_disk_total_bytes')
  PROM_OB_DISK_FREE_BYTES=$(prom_query_avg 'ob_disk_free_bytes')
  PROM_OB_PLAN_CACHE_HIT_PCT=$(prom_query_avg '100 * (sum(rate(ob_plan_cache_hit_total[1m])) / clamp_min(sum(rate(ob_plan_cache_access_total[1m])), 1e-9))')
  PROM_OB_QUERY_P95_MS=$(prom_query_avg '1000 * histogram_quantile(0.95, sum(rate(ob_query_response_time_seconds_bucket[1m])) by (le))')
  PROM_OB_WAIT_EVENTS=$(prom_query_avg 'sum(rate(ob_waitevent_wait_total[1m]))')

  # OceanBase tenant performance
  PROM_TENANT_CPU_TOTAL=$(prom_query_avg 'ob_tenant_assigned_cpu_total')
  PROM_TENANT_MEM_TOTAL_BYTES=$(prom_query_avg 'ob_tenant_assigned_mem_total')
  PROM_TENANT_DISK_DATA_BYTES=$(prom_query_avg 'ob_tenant_disk_data_size')
  PROM_TENANT_DISK_LOG_BYTES=$(prom_query_avg 'ob_tenant_disk_log_size')
}

###############################################################################
# Helper: parse sysbench output
###############################################################################
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

  TPS=${TPS:-0}; P95=${P95:-0}; AVG_LAT=${AVG_LAT:-0}; TOTAL_Q=${TOTAL_Q:-0}; ERRS=${ERRS:-0}
}

###############################################################################
# Main
###############################################################################
echo "=========================================="
echo " OceanBase Benchmark (nmysql spec)"
echo " Label:   ${CLUSTER_LABEL}"
echo " Host:    ${MYSQL_HOST}:${MYSQL_PORT}"
echo " Tables:  ${TABLES} × ${TABLE_SIZE} rows"
echo " Run:     ${RUN_TIME}s per case"
echo " Warmup:  ${WARMUP_TIME}s (${WARMUP_THREADS} threads)"
echo " Threads: ${THREADS_LIST}"
echo " Workloads: ${WORKLOADS}"
echo "=========================================="

# Ensure database exists
echo "[0/4] Ensuring database '${MYSQL_DB}' exists..."
mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
  -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DB};" 2>/dev/null || true

# Step 1: Prepare data
echo "[1/4] Preparing test data (${TABLES} tables × ${TABLE_SIZE} rows, ~10 GB+)..."
echo "      Cleaning up any existing tables first..."
$SYSBENCH_BASE --threads="$PREPARE_THREADS" oltp_read_only cleanup 2>/dev/null || true

echo "      Inserting data with ${PREPARE_THREADS} threads..."
$SYSBENCH_BASE --threads="$PREPARE_THREADS" oltp_read_only prepare
if [ $? -ne 0 ]; then
  echo "ERROR: Data preparation failed!" >&2
  exit 1
fi
echo "      Data preparation complete."

# Step 2: Buffer pool warmup
echo "[2/4] Running buffer pool warmup (${WARMUP_THREADS} threads, ${WARMUP_TIME}s, results discarded)..."
$SYSBENCH_BASE --threads="$WARMUP_THREADS" --time="$WARMUP_TIME" oltp_read_only run > /dev/null 2>&1
echo "      Warmup complete."

# Step 3+4: Run benchmark matrix
# Initialize CSV
echo "timestamp,cluster_label,workload,threads,tps,p95_ms,avg_latency_ms,total_queries,errors,exit_code,status,cpu_usage_pct,memory_usage_pct,disk_io_mbps,prom_host_load1,prom_host_cpu_pct,prom_host_mem_used_bytes,prom_host_mem_pct,prom_host_iops,prom_host_io_time_us,prom_host_io_throughput_bytes_per_s,prom_host_net_throughput_bytes_per_s,prom_ob_server_num,prom_ob_active_sessions,prom_ob_all_sessions,prom_ob_cpu_assigned_pct,prom_ob_mem_assigned_pct,prom_ob_disk_total_bytes,prom_ob_disk_free_bytes,prom_ob_plan_cache_hit_pct,prom_ob_query_p95_ms,prom_ob_wait_events,prom_tenant_cpu_total,prom_tenant_mem_total_bytes,prom_tenant_disk_data_bytes,prom_tenant_disk_log_bytes" > "$CSV_FILE"

for workload in $WORKLOADS; do
  if [ "$workload" = "oltp_read_only" ]; then
    echo "[3/4] Running Read-Only gradient stress test..."
  else
    echo "[4/4] Running Read-Write gradient stress test..."
  fi

  for threads in $THREADS_LIST; do
    echo "  -> ${workload} threads=${threads} (${RUN_TIME}s)..."
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Pre-metrics
    snap_dir=$(mktemp -d)
    collect_pre_metrics "$snap_dir"

    # Run sysbench
    result_file=$(mktemp)
    $SYSBENCH_BASE --threads="$threads" --time="$RUN_TIME" "$workload" run >"$result_file" 2>&1
    rc=$?
    result="$(cat "$result_file")"
    rm -f "$result_file"

    # Post-metrics
    collect_post_metrics "$snap_dir"
    compute_metrics "$snap_dir" "$RUN_TIME"
    rm -rf "$snap_dir"

    # Prometheus metrics (cluster + tenant + host charts)
    collect_prometheus_metrics

    # Parse
    parse_sysbench "$result"

    status="ok"
    if [ "$rc" -ne 0 ]; then
      status="failed"
      echo "     FAILED (rc=$rc)" >&2
    else
      echo "     OK: TPS=$TPS P95=${P95}ms"
    fi

    echo "${now},${CLUSTER_LABEL},${workload},${threads},${TPS},${P95},${AVG_LAT},${TOTAL_Q},${ERRS},${rc},${status},${METRIC_CPU},${METRIC_MEM},${METRIC_DISK},${PROM_HOST_LOAD1},${PROM_HOST_CPU_PCT},${PROM_HOST_MEM_USED_BYTES},${PROM_HOST_MEM_PCT},${PROM_HOST_IOPS},${PROM_HOST_IO_TIME_US},${PROM_HOST_IO_THROUGHPUT},${PROM_HOST_NET_THROUGHPUT},${PROM_OB_SERVER_NUM},${PROM_OB_ACTIVE_SESSIONS},${PROM_OB_ALL_SESSIONS},${PROM_OB_CPU_ASSIGNED_PCT},${PROM_OB_MEM_ASSIGNED_PCT},${PROM_OB_DISK_TOTAL_BYTES},${PROM_OB_DISK_FREE_BYTES},${PROM_OB_PLAN_CACHE_HIT_PCT},${PROM_OB_QUERY_P95_MS},${PROM_OB_WAIT_EVENTS},${PROM_TENANT_CPU_TOTAL},${PROM_TENANT_MEM_TOTAL_BYTES},${PROM_TENANT_DISK_DATA_BYTES},${PROM_TENANT_DISK_LOG_BYTES}" >> "$CSV_FILE"

    # Cool-down
    echo "     Sleeping ${SLEEP_BETWEEN}s..."
    sleep "$SLEEP_BETWEEN"
  done
done

echo "=========================================="
echo " Benchmark complete!"
echo " CSV: ${CSV_FILE}"
echo "=========================================="
cat "$CSV_FILE"
