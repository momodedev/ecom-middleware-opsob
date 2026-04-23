#!/usr/bin/env bash
###############################################################################
# run_oceanbase_benchmark_nmysql_s.sh
#
# OceanBase standalone sysbench benchmark (nmysql-style matrix)
#
# Test profile:
#   - 90 tables x 500,000 rows
#   - Warmup: 120s (50 threads, read_only, discarded)
#   - Run time: 300s per case
#   - Workloads: oltp_read_only, oltp_read_write
#   - Thread ladder: 20, 50, 100, 200
#   - 30s cooldown between cases
#
# Usage:
#   ./run_oceanbase_benchmark_nmysql_s.sh <cluster_label> <mysql_host> \
#       <mysql_user> <mysql_password> <mysql_db> [observer_ips]
#
# Example:
#   ./run_oceanbase_benchmark_nmysql_s.sh d16s_v6_obs 13.83.163.165 \
#       root@sys 'OceanBase#!123' sbtest "13.83.163.165"
###############################################################################
set -Eeuo pipefail

if [ "$#" -lt 5 ]; then
  echo "Usage: $0 <cluster_label> <mysql_host> <mysql_user> <mysql_password> <mysql_db> [observer_ips]" >&2
  exit 1
fi

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $c" >&2
    exit 1
  }
}

CLUSTER_LABEL="$1"
MYSQL_HOST="$2"
MYSQL_USER="$3"
MYSQL_PASSWORD="$4"
MYSQL_DB="$5"
OBSERVER_IPS="${6:-$MYSQL_HOST}"

MYSQL_PORT="${MYSQL_PORT:-2881}"
TABLE_SIZE="${TABLE_SIZE:-500000}"
TABLES="${TABLES:-90}"
RUN_TIME="${RUN_TIME:-300}"
WARMUP_TIME="${WARMUP_TIME:-120}"
WARMUP_THREADS="${WARMUP_THREADS:-50}"
PREPARE_THREADS="${PREPARE_THREADS:-50}"
REPORT_INTERVAL="${REPORT_INTERVAL:-5}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-30}"
SKIP_PREPARE="${SKIP_PREPARE:-0}"
COLLECT_HOST_METRICS="${COLLECT_HOST_METRICS:-1}"
THREADS_LIST="${THREADS_LIST:-20 50 100 200}"
WORKLOADS="${WORKLOADS:-oltp_read_only oltp_write_only oltp_read_write}"
AUTO_COMPARE_REPORT="${AUTO_COMPARE_REPORT:-1}"
RW_P95_ALERT_THRESHOLD_MS="${RW_P95_ALERT_THRESHOLD_MS:-200}"

OUTPUT_DIR="${OUTPUT_DIR:-/tmp/oceanbase-bench}"
CSV_FILE="${OUTPUT_DIR}/${CLUSTER_LABEL}.csv"
LOG_FILE="${OUTPUT_DIR}/${CLUSTER_LABEL}.log"
REPORT_FILE="${OUTPUT_DIR}/${CLUSTER_LABEL}.analysis.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTO_REPORT_PY="${AUTO_REPORT_PY:-${SCRIPT_DIR}/benchmark_auto_report.py}"

SSH_KEY="${SSH_KEY:-}"
SSH_USER="${SSH_USER:-admin}"
SSH_PORT="${SSH_PORT:-22}"
SSH_USERS="${SSH_USERS:-${SSH_USER} azureadmin admin root}"
SSH_PORTS="${SSH_PORTS:-${SSH_PORT} 6666 22}"
SSH_KEY_CANDIDATES="${SSH_KEY_CANDIDATES:-$HOME/.ssh/id_rsa_vm_ob $HOME/.ssh/id_rsa $HOME/.ssh/id_ed25519}"

if [ -n "$SSH_KEY" ]; then
  SSH_KEY_CANDIDATES="$SSH_KEY $SSH_KEY_CANDIDATES"
fi

require_cmd awk
require_cmd grep
require_cmd sed
require_cmd date
require_cmd mktemp
require_cmd sysbench

if command -v mysql >/dev/null 2>&1; then
  SQL_CLIENT="mysql"
elif command -v obclient >/dev/null 2>&1; then
  SQL_CLIENT="obclient"
else
  echo "ERROR: mysql or obclient client is required for database bootstrap" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
: > "$LOG_FILE"

log() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$ts] $*" | tee -a "$LOG_FILE"
}

count_words() {
  awk '{print NF}' <<<"$1"
}

validate_workloads() {
  local wl
  for wl in $WORKLOADS; do
    case "$wl" in
      oltp_read_only|oltp_write_only|oltp_read_write)
        ;;
      *)
        echo "ERROR: unsupported workload '${wl}'. Supported: oltp_read_only oltp_write_only oltp_read_write" >&2
        return 1
        ;;
    esac
  done
}

SYSBENCH_BASE=(
  sysbench
  --db-driver=mysql
  --mysql-host="${MYSQL_HOST}"
  --mysql-port="${MYSQL_PORT}"
  --mysql-user="${MYSQL_USER}"
  --mysql-password="${MYSQL_PASSWORD}"
  --mysql-db="${MYSQL_DB}"
  --tables="${TABLES}"
  --table-size="${TABLE_SIZE}"
  --events=0
  --report-interval="${REPORT_INTERVAL}"
  --db-ps-mode=disable
)

collect_pre_metrics() {
  local snap_dir="$1"
  local got=0
  for mip in $OBSERVER_IPS; do
    local ok=0
    local out_file="${snap_dir}/before_${mip}"
    for su in $SSH_USERS; do
      for sp in $SSH_PORTS; do
        for sk in $SSH_KEY_CANDIDATES __NO_KEY__; do
          local ssh_cmd
          ssh_cmd=(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -p "$sp")
          if [ "$sk" != "__NO_KEY__" ] && [ -f "$sk" ]; then
            ssh_cmd+=( -i "$sk" )
          elif [ "$sk" != "__NO_KEY__" ]; then
            continue
          fi
          if "${ssh_cmd[@]}" "${su}@${mip}" \
            "head -1 /proc/stat; echo ===SEP===; cat /proc/diskstats" \
            > "$out_file" 2>/dev/null; then
            ok=1
            break
          fi
        done
        [ "$ok" -eq 1 ] && break
      done
      [ "$ok" -eq 1 ] && break
    done
    if [ "$ok" -eq 1 ]; then
      got=1
    else
      rm -f "$out_file"
      log "WARN: pre-metrics snapshot failed for ${mip} (checked users: ${SSH_USERS}; ports: ${SSH_PORTS})"
    fi
  done
  [ "$got" -eq 1 ]
}

collect_post_metrics() {
  local snap_dir="$1"
  local got=0
  for mip in $OBSERVER_IPS; do
    local ok=0
    local out_file="${snap_dir}/after_${mip}"
    for su in $SSH_USERS; do
      for sp in $SSH_PORTS; do
        for sk in $SSH_KEY_CANDIDATES __NO_KEY__; do
          local ssh_cmd
          ssh_cmd=(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -p "$sp")
          if [ "$sk" != "__NO_KEY__" ] && [ -f "$sk" ]; then
            ssh_cmd+=( -i "$sk" )
          elif [ "$sk" != "__NO_KEY__" ]; then
            continue
          fi
          if "${ssh_cmd[@]}" "${su}@${mip}" \
            "head -1 /proc/stat; echo ===SEP===; cat /proc/diskstats; echo ===SEP===; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo" \
            > "$out_file" 2>/dev/null; then
            ok=1
            break
          fi
        done
        [ "$ok" -eq 1 ] && break
      done
      [ "$ok" -eq 1 ] && break
    done
    if [ "$ok" -eq 1 ]; then
      got=1
    else
      rm -f "$out_file"
      log "WARN: post-metrics snapshot failed for ${mip} (checked users: ${SSH_USERS}; ports: ${SSH_PORTS})"
    fi
  done
  [ "$got" -eq 1 ]
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

    local c m d
    c=$(awk '
      FNR==1 && NR==1 {for(i=2;i<=NF;i++) tb+=$i; ib=$5}
      FNR==1 && NR!=1 {for(i=2;i<=NF;i++) ta+=$i; ia=$5}
      END {
        dt=ta-tb; didle=ia-ib;
        if (dt>0) printf "%.1f", 100*(1-didle/dt); else print "0.0"
      }
    ' "$bf" "$af")
    c="${c:-0.0}"
    cpu_sum=$(awk "BEGIN{printf \"%.1f\",${cpu_sum}+${c}}")

    m=$(awk '
      BEGIN{p=0}
      /===SEP===/{p++; next}
      p>=2 && /^MemTotal/{t=$2}
      p>=2 && /^MemAvailable/{a=$2}
      END{if(t>0) printf "%.1f",(t-a)/t*100; else print "0.0"}
    ' "$af")
    m="${m:-0.0}"
    mem_sum=$(awk "BEGIN{printf \"%.1f\",${mem_sum}+${m}}")

    d=$(awk -v dur="$duration" '
      BEGIN{ph="b"}
      FILENAME==ARGV[1] && /===SEP===/{ph="bd"; next}
      FILENAME==ARGV[2] && /===SEP===/{
        if (ph=="a") ph="am"; else ph="a";
        next
      }
      {
        if ($3 ~ /^(sd[a-z]|nvme[0-9]+n[0-9]+)$/) {
          if (FILENAME==ARGV[1] && ph=="bd") {br+=$6; bw+=$10}
          if (FILENAME==ARGV[2] && ph=="a")  {ar+=$6; aw+=$10}
        }
      }
      END{
        delta=(ar-br)+(aw-bw);
        if (dur>0) printf "%.2f", delta*512/1024/1024/dur; else print "0.00"
      }
    ' "$bf" "$af")
    d="${d:-0.00}"
    disk_sum=$(awk "BEGIN{printf \"%.2f\",${disk_sum}+${d}}")
  done

  if [ "$obs_count" -gt 0 ]; then
    METRIC_CPU=$(awk "BEGIN{printf \"%.1f\",${cpu_sum}/${obs_count}}")
    METRIC_MEM=$(awk "BEGIN{printf \"%.1f\",${mem_sum}/${obs_count}}")
    METRIC_DISK=$(awk "BEGIN{printf \"%.2f\",${disk_sum}/${obs_count}}")
    METRIC_SAMPLE_OK="1"
  else
    METRIC_CPU="0.0"
    METRIC_MEM="0.0"
    METRIC_DISK="0.00"
    METRIC_SAMPLE_OK="0"
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

  TPS="${TPS:-0}"
  P95="${P95:-0}"
  AVG_LAT="${AVG_LAT:-0}"
  TOTAL_Q="${TOTAL_Q:-0}"
  ERRS="${ERRS:-0}"
}

log "=========================================="
log "OceanBase Benchmark (nmysql standalone)"
log "Cluster:   ${CLUSTER_LABEL}"
log "Host:      ${MYSQL_HOST}:${MYSQL_PORT}"
log "Tables:    ${TABLES} x ${TABLE_SIZE}"
log "Run:       ${RUN_TIME}s per case"
log "Warmup:    ${WARMUP_TIME}s (${WARMUP_THREADS} threads)"
log "Threads:   ${THREADS_LIST}"
log "Workloads: ${WORKLOADS}"
log "Skip prepare: ${SKIP_PREPARE}"
log "Collect host metrics: ${COLLECT_HOST_METRICS}"
log "Auto compare report: ${AUTO_COMPARE_REPORT}"
log "RW p95 alert threshold(ms): ${RW_P95_ALERT_THRESHOLD_MS}"
log "CSV:       ${CSV_FILE}"
log "LOG:       ${LOG_FILE}"
log "REPORT:    ${REPORT_FILE}"
log "=========================================="

validate_workloads

total_workloads="$(count_words "$WORKLOADS")"
total_threads="$(count_words "$THREADS_LIST")"
total_cases=$((total_workloads * total_threads))
done_cases=0
failed_cases=0

log "Matrix:    ${total_workloads} workloads x ${total_threads} thread levels = ${total_cases} cases"

log "[0/4] Ensuring database '${MYSQL_DB}' exists..."
if [ "$SQL_CLIENT" = "mysql" ]; then
  mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
    -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DB};" >/dev/null 2>&1 || true
else
  obclient -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
    -e "CREATE DATABASE IF NOT EXISTS ${MYSQL_DB};" >/dev/null 2>&1 || true
fi

if [ "$SKIP_PREPARE" = "1" ]; then
  log "[1/4] SKIP_PREPARE=1, reusing existing benchmark data"
else
  log "[1/4] Preparing data (${TABLES} tables x ${TABLE_SIZE} rows)..."
  "${SYSBENCH_BASE[@]}" --threads="$PREPARE_THREADS" oltp_read_only cleanup >/dev/null 2>&1 || true
  "${SYSBENCH_BASE[@]}" --threads="$PREPARE_THREADS" oltp_read_only prepare | tee -a "$LOG_FILE"
fi

log "[2/4] Warmup (${WARMUP_THREADS} threads, ${WARMUP_TIME}s)..."
"${SYSBENCH_BASE[@]}" --threads="$WARMUP_THREADS" --time="$WARMUP_TIME" oltp_read_only run >/dev/null 2>&1

echo "timestamp,label,workload,threads,tps,p95_latency,avg_latency,total_queries,errors,rc,status,cpu_pct,mem_pct,disk_io_mbps" > "$CSV_FILE"

workload_idx=0
for workload in $WORKLOADS; do
  workload_idx=$((workload_idx + 1))
  case "$workload" in
    oltp_read_only)
      workload_desc="read-only"
      ;;
    oltp_read_write)
      workload_desc="read-write"
      ;;
    oltp_write_only)
      workload_desc="write-only"
      ;;
    *)
      workload_desc="$workload"
      ;;
  esac

  log "[workload ${workload_idx}/${total_workloads}] Running ${workload_desc} gradient stress test (${workload})"

  for threads in $THREADS_LIST; do
    done_cases=$((done_cases + 1))
    local_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log "Case [${done_cases}/${total_cases}]: workload=${workload}, threads=${threads}, duration=${RUN_TIME}s"

    snap_dir="$(mktemp -d)"
    if [ "$COLLECT_HOST_METRICS" = "1" ]; then
      collect_pre_metrics "$snap_dir" || true
    fi

    result_file="$(mktemp)"
    set +e
    "${SYSBENCH_BASE[@]}" --threads="$threads" --time="$RUN_TIME" "$workload" run >"$result_file" 2>&1
    rc=$?
    set -e

    result="$(cat "$result_file")"
    rm -f "$result_file"

    if [ "$COLLECT_HOST_METRICS" = "1" ]; then
      collect_post_metrics "$snap_dir" || true
      compute_metrics "$snap_dir" "$RUN_TIME"
      if [ "${METRIC_SAMPLE_OK:-0}" = "0" ]; then
        log "WARN: host metrics unavailable for case workload=${workload}, threads=${threads}; CSV metrics fields set to 0"
      fi
    else
      METRIC_CPU="0.0"
      METRIC_MEM="0.0"
      METRIC_DISK="0.00"
      METRIC_SAMPLE_OK="0"
    fi
    rm -rf "$snap_dir"

    parse_sysbench "$result"

    status="ok"
    if [ "$rc" -ne 0 ]; then
      status="failed"
      failed_cases=$((failed_cases + 1))
      log "FAILED: rc=${rc}"
    else
      log "OK: TPS=${TPS}, P95=${P95}ms, Avg=${AVG_LAT}ms"
    fi

    echo "${local_now},${CLUSTER_LABEL},${workload},${threads},${TPS},${P95},${AVG_LAT},${TOTAL_Q},${ERRS},${rc},${status},${METRIC_CPU},${METRIC_MEM},${METRIC_DISK}" >> "$CSV_FILE"

    log "Cooling down ${SLEEP_BETWEEN}s"
    sleep "$SLEEP_BETWEEN"
  done
done

log "=========================================="
log "Benchmark complete"
log "CSV: ${CSV_FILE}"
if [ "$failed_cases" -gt 0 ]; then
  log "FAILED CASES: ${failed_cases}/${total_cases}"
  log "=========================================="
  cat "$CSV_FILE"
  exit 2
fi
log "All cases succeeded: ${done_cases}/${total_cases}"
log "=========================================="
cat "$CSV_FILE"

if [ "$AUTO_COMPARE_REPORT" = "1" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PY_BIN="python3"
  elif command -v python >/dev/null 2>&1; then
    PY_BIN="python"
  else
    PY_BIN=""
  fi

  if [ -n "$PY_BIN" ] && [ -f "$AUTO_REPORT_PY" ]; then
    log "[report] Generating auto analysis report..."
    "$PY_BIN" "$AUTO_REPORT_PY" \
      --csv "$CSV_FILE" \
      --output "$REPORT_FILE" \
      --rw-p95-threshold "$RW_P95_ALERT_THRESHOLD_MS" \
      | tee -a "$LOG_FILE"
    log "[report] Done: ${REPORT_FILE}"
  else
    log "WARN: auto report skipped (python or report script missing). script=${AUTO_REPORT_PY}"
  fi
fi
