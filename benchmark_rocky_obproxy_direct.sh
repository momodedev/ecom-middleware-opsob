#!/bin/bash
set -euo pipefail

echo "=== Rocky OBProxy Benchmark ==="
echo "Start time: $(date)"
echo "Configuration:"
echo "  Proxy Host: 172.17.1.7"
echo "  Proxy Port: 2883"
echo "  Cluster: ob_cluster (3 nodes)"
echo ""

# Test connection to OBProxy
echo "Testing connection to OBProxy..."
mysql -h 172.17.1.7 -P 2883 -u root@sbtest_tenant -p'OceanBase#!123' -e "SELECT 1;" 2>&1 | head -5

echo ""
echo "Connection successful! Running benchmark..."
echo ""

# Run sysbench benchmark with 5 thread levels, 3 workload types (read-only, write-only, read-write)
# Results will be logged to /tmp/oceanbase-bench/d8s_v5_rocky_obproxy.csv

OUTPUT_DIR="/tmp/oceanbase-bench"
mkdir -p "$OUTPUT_DIR"
OUTPUT_CSV="$OUTPUT_DIR/d8s_v5_rocky_obproxy.csv"

# Write CSV header
cat > "$OUTPUT_CSV" << 'EOF'
timestamp,label,workload,threads,tps,p95_latency,avg_latency,total_queries,errors,rc,status,cpu_pct,mem_pct,disk_io_mbps
EOF

THREADS=(16 32 64 128 256)
WORKLOADS=(oltp_read_only oltp_write_only oltp_read_write)

for workload in "${WORKLOADS[@]}"; do
  for threads in "${THREADS[@]}"; do
    echo ""
    echo "=== Running: workload=$workload threads=$threads ==="
    
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    RESULT_FILE=$(mktemp)
    
    # Run sysbench
    (
      sysbench /usr/share/sysbench/${workload}.lua \
        --db-driver=mysql \
        --mysql-host=172.17.1.7 \
        --mysql-port=2883 \
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
    
    # System metrics (simplified - all zeros for now)
    CPU="0.0"
    MEM="0.0"
    DISK="0.00"
    
    # Append to CSV
    echo "$NOW,d8s_v5_rocky_obproxy,$workload,$threads,$TPS,$P95,$AVG,$TQ,$ERR,$RC,$STATUS,$CPU,$MEM,$DISK" >> "$OUTPUT_CSV"
    
    echo "Completed: TPS=$TPS P95=$P95 Status=$STATUS"
    
    rm -f "$RESULT_FILE"
  done
done

echo ""
echo "=== Benchmark Complete ==="
echo "Results: $OUTPUT_CSV"
echo "End time: $(date)"
echo "Line count: $(wc -l < "$OUTPUT_CSV")"
