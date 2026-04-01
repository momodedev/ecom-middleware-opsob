#!/bin/bash
set -euo pipefail

echo "=== Rocky OBProxy Benchmark (via port 2883) ==="
echo "Start time: $(date)"
echo "Configuration:"
echo "  Host: 172.17.1.7"
echo "  Port: 2883 (OBProxy)"
echo "  Cluster: 3-node Rocky cluster"
echo ""

# Test connection through OBProxy
echo "Testing connection through OBProxy..."
mysql -h 172.17.1.7 -P 2883 -u "root@sbtest_tenant#ob_cluster" -p'OceanBase#!123' -e "SELECT 1 as connected;" 2>&1 | head -3

echo ""
echo "Connection successful! Running benchmark..."
echo ""

# Run sysbench benchmark with 5 thread levels, 3 workload types
OUTPUT_DIR="/tmp/oceanbase-bench"
mkdir -p "$OUTPUT_DIR"
OUTPUT_CSV="$OUTPUT_DIR/d8s_v5_rocky_obproxy.csv"

# Write CSV header
cat > "$OUTPUT_CSV" << 'EOF'
timestamp,label,workload,threads,tps,p95_latency,avg_latency,total_queries,errors,rc,status,cpu_pct,mem_pct,disk_io_mbps
EOF

THREADS=(16 32 64 128 256)
WORKLOADS=(oltp_read_only oltp_write_only oltp_read_write)

TEST_COUNT=0
for workload in "${WORKLOADS[@]}"; do
  for threads in "${THREADS[@]}"; do
    TEST_COUNT=$((TEST_COUNT + 1))
    echo "[$(date)] Test $TEST_COUNT/15: workload=$workload threads=$threads"

    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    RESULT_FILE=$(mktemp)

    # Run sysbench via OBProxy — capture real exit code; override OB session timeouts
    # so write workloads don't abort immediately (cluster ob_trx_timeout may be very short)
    set +e
    sysbench /usr/share/sysbench/${workload}.lua \
      --db-driver=mysql \
      --mysql-host=172.17.1.7 \
      --mysql-port=2883 \
      --mysql-user="root@sbtest_tenant#ob_cluster" \
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

    # Parse results — default to 0 to avoid empty CSV cells
    TPS=$(echo "$RESULT" | awk -F'[()]' '/transactions:/{gsub(/ per sec\./, "", $2); print $2}' | awk '{print $1}' | tail -1); TPS=${TPS:-0}
    P95=$(echo "$RESULT" | awk '/95th percentile:/{print $3}' | tail -1); P95=${P95:-0}
    AVG=$(echo "$RESULT" | awk '/avg:/{print $2}' | tail -1); AVG=${AVG:-0}
    TQ=$(echo "$RESULT" | awk '/^[[:space:]]*queries:[[:space:]]+[0-9]+/{print $2}' | tail -1); TQ=${TQ:-0}
    ERR=$(echo "$RESULT" | awk -F': ' '/ignored errors:/{print $2}' | awk '{print $1}' | tail -1); ERR=${ERR:-0}

    STATUS="ok"
    [ "$RC" -ne 0 ] && STATUS="failed"

    # Save debug log when run failed or produced no TPS
    if [[ "$RC" -ne 0 || "$TPS" == "0" ]]; then
      DBG="/tmp/oceanbase-bench/debug_proxy_${workload}_t${threads}.log"
      cp "$RESULT_FILE" "$DBG"
      echo "  => RC=$RC (debug saved: $DBG)"
      tail -4 "$DBG" | sed 's/^/     /'
    fi

    CPU="0.0"
    MEM="0.0"
    DISK="0.00"

    echo "$NOW,d8s_v5_rocky_obproxy,$workload,$threads,$TPS,$P95,$AVG,$TQ,$ERR,$RC,$STATUS,$CPU,$MEM,$DISK" >> "$OUTPUT_CSV"

    echo "  => TPS=$TPS P95=$P95 Status=$STATUS"

    rm -f "$RESULT_FILE"
  done
done

echo ""
echo "=== Benchmark Complete ==="
echo "Results: $OUTPUT_CSV"
echo "End time: $(date)"
echo "Total tests: $TEST_COUNT"
if [ -f "$OUTPUT_CSV" ]; then
  echo "CSV lines: $(wc -l < "$OUTPUT_CSV")"
  echo ""
  echo "Last few results:"
  tail -3 "$OUTPUT_CSV"
fi
