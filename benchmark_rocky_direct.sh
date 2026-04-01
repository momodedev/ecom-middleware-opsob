#!/bin/bash
set -euo pipefail

echo "=== Rocky Direct Benchmark (No OBProxy) ==="
echo "Start time: $(date)"
echo "Configuration:"
echo "  Host: 172.17.1.7"
echo "  Port: 2881 (Direct OceanBase)"
echo "  Cluster: 3-node Rocky cluster"
echo ""

# Test connection to OceanBase directly
echo "Testing connection to OceanBase..."
mysql -h 172.17.1.7 -P 2881 -u root@sbtest_tenant -p'OceanBase#!123' -e "SELECT 1 as connected;" 2>&1 | head -3

echo ""
echo "Connection successful! Running benchmark..."
echo ""

# Run sysbench benchmark with 5 thread levels, 3 workload types
OUTPUT_DIR="/tmp/oceanbase-bench"
mkdir -p "$OUTPUT_DIR"
OUTPUT_CSV="$OUTPUT_DIR/d8s_v5_rocky_direct.csv"

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
    
    # Run sysbench
    (
      sysbench /usr/share/sysbench/${workload}.lua \
        --db-driver=mysql \
        --mysql-host=172.17.1.7 \
        --mysql-port=2881 \
        --mysql-user=root@sbtest_tenant \
        --mysql-password='OceanBase#!123' \
        --mysql-db=sbtest \
        --tables=10 \
        --table-size=100000 \
        --threads=$threads \
        --time=120 \
        --report-interval=10 \
        --db-ps-mode=disable \
        run
    ) >"$RESULT_FILE" 2>&1 || true
    
    RESULT=$(cat "$RESULT_FILE")
    RC=$?
    
    # Parse results
    TPS=$(echo "$RESULT" | awk -F'[()]' '/transactions:/{gsub(/ per sec\./, "", $2); print $2}' | awk '{print $1}' | tail -1 || echo "0")
    P95=$(echo "$RESULT" | awk '/95th percentile:/{print $3}' | tail -1 || echo "0")
    AVG=$(echo "$RESULT" | awk '/avg:/{print $2}' | tail -1 || echo "0")
    TQ=$(echo "$RESULT" | awk '/^[[:space:]]*queries:[[:space:]]+[0-9]+/{print $2}' | tail -1 || echo "0")
    ERR=$(echo "$RESULT" | awk -F': ' '/ignored errors:/{print $2}' | awk '{print $1}' | tail -1 || echo "0")
    
    STATUS="ok"
    [ "$RC" -ne 0 ] && STATUS="failed"
    
    # System metrics (simplified)
    CPU="0.0"
    MEM="0.0"
    DISK="0.00"
    
    # Append to CSV
    echo "$NOW,d8s_v5_rocky_direct,$workload,$threads,$TPS,$P95,$AVG,$TQ,$ERR,$RC,$STATUS,$CPU,$MEM,$DISK" >> "$OUTPUT_CSV"
    
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
  echo "First few results:"
  tail -3 "$OUTPUT_CSV"
fi
