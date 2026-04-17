#!/bin/bash
# Apply recommended PerfTuning Parameters to OceanBase v4.5.0

PASS='OceanBase#!123'
OB="obclient -h127.0.0.1 -P2881 -uroot@sys -p${PASS} -Doceanbase -A"

run_sql() {
    echo "$1" | $OB 2>&1
}

echo "============================================================"
echo "=== Applying Recommended Performance Tuning Parameters ==="
echo "============================================================"

echo ""
echo "--- Current parameter values (BEFORE) ---"
run_sql "SELECT name, value FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN (
  'enable_adaptive_plan_cache','use_large_pages','freeze_trigger_percentage',
  'ob_enable_batched_multi_statement','compaction_high_thread_score',
  'net_thread_count','cpu_quota_concurrency'
) ORDER BY name;"

echo ""
echo "--- Applying tuning changes ---"

# Change 1: enable_adaptive_plan_cache
echo ""
echo "1. Setting enable_adaptive_plan_cache = True"
run_sql "ALTER SYSTEM SET enable_adaptive_plan_cache = True;"

# Change 2: use_large_pages
echo ""
echo "2. Setting use_large_pages = true"
run_sql "ALTER SYSTEM SET use_large_pages = true;"

# Change 3: freeze_trigger_percentage
echo ""
echo "3. Setting freeze_trigger_percentage = 15 (from 20%)"
run_sql "ALTER SYSTEM SET freeze_trigger_percentage = 15;"

# Change 4: ob_enable_batched_multi_statement
echo ""
echo "4. Setting ob_enable_batched_multi_statement = True"
run_sql "ALTER SYSTEM SET ob_enable_batched_multi_statement = True;"

# Change 5: compaction_high_thread_score
echo ""
echo "5. Setting compaction_high_thread_score = 4 (for OLTP)"
run_sql "ALTER SYSTEM SET compaction_high_thread_score = 4;"

# Change 6: net_thread_count (set to 8 for good network performance)
echo ""
echo "6. Setting net_thread_count = 8 (from 0 auto)"
run_sql "ALTER SYSTEM SET net_thread_count = 8;"

# Change 7: cpu_quota_concurrency (increase to 12)
echo ""
echo "7. Setting cpu_quota_concurrency = 12 (from 10)"
run_sql "ALTER SYSTEM SET cpu_quota_concurrency = 12;"

echo ""
echo ""
echo "--- Updated parameter values (AFTER) ---"
run_sql "SELECT name, value FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN (
  'enable_adaptive_plan_cache','use_large_pages','freeze_trigger_percentage',
  'ob_enable_batched_multi_statement','compaction_high_thread_score',
  'net_thread_count','cpu_quota_concurrency'
) ORDER BY name;"

echo ""
echo "--- Waiting for parameters to propagate (10 seconds) ---"
sleep 10

echo ""
echo "--- Final verification ---"
run_sql "SELECT name, value FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN (
  'enable_adaptive_plan_cache','use_large_pages','freeze_trigger_percentage',
  'ob_enable_batched_multi_statement','compaction_high_thread_score',
  'net_thread_count','cpu_quota_concurrency'
) ORDER BY name;"

echo ""
echo "=== Tuning parameters applied successfully ==="
