#!/bin/bash
# Generate comparison report from benchmark CSVs

set -euo pipefail

BASELINE_CSV="${1:-/tmp/oceanbase-bench/d8s_v6.csv}"
COMPARE_CSV="${ 2:-/tmp/oceanbase-bench/d8s_v5_rocky_direct.csv}"
OUTPUT_FILE="${3:-/tmp/oceanbase-bench/COMPARISON_ANALYSIS.txt}"

if [ ! -f "$BASELINE_CSV" ]; then
  echo "ERROR: Baseline CSV not found: $BASELINE_CSV"
  echo "Available files:"
  ls -la /tmp/oceanbase-bench/*.csv 2>/dev/null || echo "No CSVs found"
  exit 1
fi

if [ ! -f "$COMPARE_CSV" ]; then
  echo "ERROR: Comparison CSV not found: $COMPARE_CSV"
  exit 1
fi

echo "Parsing CSVs..."
echo "Baseline: $BASELINE_CSV"
echo "Comparison: $COMPARE_CSV"
echo ""

{
  echo "=============================================="
  echo "Rocky OceanBase Performance Comparison"
  echo "=============================================="
  echo "Generated: $(date)"
  echo ""
  echo "Baseline CSV:    $BASELINE_CSV"
  echo "Comparison CSV:  $COMPARE_CSV"
  echo ""
  
  # Extract and compare by workload and thread count
  for workload in oltp_read_only oltp_write_only oltp_read_write; do
    echo ""
    echo "============================================"
    echo "Workload: $workload"
    echo "============================================"
    
    # Parse baseline data
    baseline_data=$(awk -F',' -v wl="$workload" '$3 == wl && NF >= 5 {print $4, $5, $6}' "$BASELINE_CSV" | tail -5)
    compare_data=$(awk -F',' -v wl="$workload" '$3 == wl && NF >= 5 {print $4, $5, $6}' "$COMPARE_CSV" | tail -5)
    
    echo ""
    echo "Threads | Baseline TPS | Post-Config TPS | Change % | Baseline P95 | Post-Config P95"
    echo "--------|--------------|-----------------|----------|--------------|----------------"
    
    while read baseline_line; do
      [ -z "$baseline_line" ] && continue
      baseline_threads=$(echo "$baseline_line" | awk '{print $1}')
      baseline_tps=$(echo "$baseline_line" | awk '{print $2}')
      baseline_p95=$(echo "$baseline_line" | awk '{print $3}')
      
      # Find matching comparison line
      compare_line=$(echo "$compare_data" | grep "^$baseline_threads ")
      if [ -n "$compare_line" ]; then
        compare_tps=$(echo "$compare_line" | awk '{print $2}')
        compare_p95=$(echo "$compare_line" | awk '{print $3}')
        
        # Calculate delta
        if [[ "$baseline_tps" =~ ^[0-9.]+$ ]] && [[ "$compare_tps" =~ ^[0-9.]+$ ]]; then
          delta=$(awk "BEGIN{printf \"%.2f\", ($compare_tps - $baseline_tps) / $baseline_tps * 100}")
        else
          delta="N/A"
        fi
        
        printf "%7d | %12s | %15s | %8s | %12s | %16s\n" "$baseline_threads" "$baseline_tps" "$compare_tps" "$delta" "$baseline_p95" "$compare_p95"
      else
        printf "%7d | %12s | %15s | %8s | %12s | %16s\n" "$baseline_threads" "$baseline_tps" "N/A" "N/A" "$baseline_p95" "N/A"
      fi
    done <<< "$baseline_data"
  done
  
  echo ""
  echo "============================================"
  echo "Raw CSV Data Summary"
  echo "============================================"
  echo ""
  echo "Baseline CSV line count: $(wc -l < "$BASELINE_CSV")"
  echo "Comparison CSV line count: $(wc -l < "$COMPARE_CSV")"
  echo ""
  
  echo "Baseline CSV (last 5 lines):"
  tail -5 "$BASELINE_CSV"
  echo ""
  
  echo "Comparison CSV (last 5 lines):"
  tail -5 "$COMPARE_CSV"
  
} | tee "$OUTPUT_FILE"

echo ""
echo "Comparison report saved to: $OUTPUT_FILE"
