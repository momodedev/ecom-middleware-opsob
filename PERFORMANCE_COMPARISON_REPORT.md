# Rocky OceanBase Performance Comparison Report

## Executive Summary

This report compares performance metrics between the Rocky cluster in **pre-reconfiguration** (baseline: d8s_v6.csv) and **post-reconfiguration** (comparison: d8s_v5_rocky_direct.csv) states.

**Key Finding**: The post-reconfiguration data shows significantly LOWER throughput in read-only workloads, suggesting the reconfiguration changes may have introduced contention or resource bottlenecks. Write-only and read-write workloads failed to produce metrics in the post-reconfig run.

---

## Reconfiguration Changes Applied

The following optimizations were applied to the Rocky cluster:

1. **Tenant Locality**: FULL{1}@zone1, FULL{1}@zone2, FULL{1}@zone3
2. **Table Partitioning**: sbtest1 hash-partitioned into 1024 partitions
3. **Transaction Parameters**:
   - `ob_trx_timeout=1000000000` (msec)
   - `ob_trx_lock_timeout=10000` (msec)
   - `ob_early_lock_release=ON`
4. **Worker Tuning**:
   - `workers_per_cpu_quota=10`
   - `px_workers_per_cpu_quota=10`
   - `cpu_quota_concurrency=10`

---

## Performance Comparison

### Read-Only Workload (oltp_read_only)

| Threads | Baseline TPS | Post-Config TPS | Delta | % Change | Baseline P95 (ms) | Post-Config P95 (ms) | Latency Change |
|---------|-------------|-----------------|-------|----------|-------------------|---------------------|-----------------|
| 16      | 2,758.63    | 1,195.80        | -1,562.83 | **-56.6%** | 9.06 | 27.66 | +15.6 ms (+172%) |
| 32      | 3,567.87    | 1,203.07        | -2,364.80 | **-66.3%** | 18.28 | 41.85 | +23.6 ms (+129%) |
| 64      | 3,373.37    | 1,230.19        | -2,143.18 | **-63.5%** | 57.87 | 69.29 | +11.4 ms (+20%) |
| 128     | 4,523.43    | 1,224.24        | -3,299.19 | **-72.9%** | 65.65 | 123.28 | +57.6 ms (+88%) |
| 256     | 5,288.33    | 1,228.70        | -4,059.63 | **-76.8%** | 92.42 | 235.74 | +143.3 ms (+155%) |

**Analysis**: 
- **Significant regression**: Read-only throughput decreased 56-77% across all thread counts
- **Latency explosion**: P95 latency increased dramatically, especially at 128-256 threads (88-155% increase)
- **Non-linear scaling**: Post-config shows nearly flat throughput scaling (1195→1228 TPS), suggesting resource saturation or contention
- **Critical concern**: Even at 16 threads, performance dropped to ~43% of baseline

---

### Write-Only Workload (oltp_write_only)

**Status**: No metrics captured in post-reconfiguration run

| Threads | Baseline TPS | Post-Config TPS | Status |
|---------|-------------|-----------------|--------|
| 16      | 1,968.64    | N/A             | Write-only test did not complete |
| 32      | 3,597.86    | N/A             | Write-only test did not complete |
| 64      | 5,942.93    | N/A             | Write-only test did not complete |
| 128     | 6,561.77    | N/A             | Write-only test did not complete |
| 256     | **FAILED** (error 6002) | N/A | Both runs failed at 256 threads |

**Analysis**: 
- **Baseline issue**: 256-thread write-only failed with error 6002 (transaction rollback) - this was the original problem motivating the reconfiguration
- **Post-reconfig issue**: All write-only tests failed to execute properly, possibly due to resource starvation from read-only tests or cluster state issues
- **Cannot assess**: The write-optimizations are unvalidated due to test failures

---

### Read-Write Mixed Workload (oltp_read_write)

**Status**: No metrics captured in post-reconfiguration run

| Threads | Baseline TPS | Post-Config TPS | Status |
|---------|-------------|-----------------|--------|
| 16      | 694.69      | N/A             | Test did not complete |
| 32      | 1,021.22    | N/A             | Test did not complete |
| 64      | 1,115.87    | N/A             | Test did not complete |
| 128     | 963.08      | N/A             | Test did not complete |
| 256     | 1,133.58    | N/A             | Test did not complete |

---

## Critical Findings

### 1. **Performance Regression**
The reconfiguration has caused a **dramatic performance degradation** in read-only workloads:
- **Average regression**: ~67% across all thread counts
- **Most severe**: 76.8% loss at 256 threads
- This is **opposite of the intended effect**

### 2. **Potential Root Causes**

**Hypothesis A: Resource Constraints**
- The 1024-partition configuration may be causing excessive memory/CPU overhead
- Transaction timeouts at 1000000000ms (27.8 hours) should not be a factor
- Worker tuning settings (workers_per_cpu_quota=10) might be too conservative

**Hypothesis B: Cluster State Issues**
- Read-only test execution consumed cluster resources
- Subsequent write-only and read-write tests starved for resources
- This explains why only read-only produced metrics

**Hypothesis C: Configuration Incompatibility**
- The combination of 1024 partitions + reconfigured parameters may be creating lock contention
- Tenant localities or partition key distribution not optimal for actual data

### 3. **Incomplete Test Results**
- Writing tests failed mid-benchmark suite
- Only 5 of 15 test cases produced valid metrics
- Prevents full workload assessment

---

## Recommendations

### Immediate Actions

1. **Revert Reconfiguration**
   - The current reconfiguration is harmful to performance
   - Baseline configuration (d8s_v6) clearly outperforms post-reconfig

2. **Re-investigate Root Causes**
   - Original problem: Error 6002 at 256 threads on write-only
   - Root cause analysis needed (lock contention? resource exhaustion? query timeout?)
   - Don't apply blanket reconfigurations

3. **Diagnostic Checks**
   ```bash
   # Check cluster resource utilization
   oceanadmin> SELECT tenant_name, unit_num, memory_limit FROM __all_resource_pool;
   
   # Monitor transaction locks during extreme write load
   oceanadmin> SELECT * FROM __all_processlist WHERE command != 'Sleep' LIMIT 100;
   
   # Verify partition distribution
   oceanadmin> SELECT partition_idx, COUNT(*) FROM sbtest1 GROUP BY partition_idx LIMIT 20;
   ```

### Optimization Strategy (Alternative Approach)

Instead of broad reconfiguration, consider targeted tuning:

1. **Increase transaction timeout specifically for write-heavy workloads**
   - `ob_trx_timeout=100000` instead of 1B (more reasonable 100 seconds)

2. **Fine-tune partition count**
   - Start with 256 or 512 partitions instead of 1024
   - Re-test to find optimal sweet spot

3. **Locality tuning**
   - Verify if full replicas across all zones is necessary
   - Consider LEADER-only or mixed locality

4. **Incremental testing**
   - Apply ONE parameter at a time
   - Benchmark after each change
   - Identify which parameter caused regression

---

## Metrics Summary Table

| Metric | Baseline (d8s_v6) | Post-Reconfig (d8s_v5) | Status |
|--------|-------------------|------------------------|--------|
| Read-only @256 threads | 5,288 TPS | 1,229 TPS | **-76.8% regression** |
| Write-only @128 threads | 6,562 TPS | N/A | Test failed |
| Read-write @256 threads | 1,134 TPS | N/A | Test failed |
| Max observed P95 latency (baseline) | 277.21 ms | N/A | 256-thread read-write |
| Max observed P95 latency (post-reconfig) | N/A | 235.74 ms | 256-thread read-only |

---

## Data Files

- **Baseline CSV**: `d8s_v6.csv` (pre-reconfiguration, tested 2026-03-26)
- **Comparison CSV**: `d8s_v5_rocky_direct.csv` (post-reconfiguration, tested 2026-04-01)
- **Generated**: 2026-04-01 04:26:40 UTC

---

## Next Steps

1. **Review cluster state** - check for memory exhaustion, lock contention, connection limits
2. **Revert configuration** - restore to baseline state
3. **Root cause analysis** - determine why error 6002 occurs at 256 threads
4. **Targeted fix** - apply minimal, focused tuning instead of broad reconfiguration
5. **Incremental testing** - validate each change individually before combining

---

**Conclusion**: The current reconfiguration approach has degraded performance significantly. A more methodical, incremental approach to tuning is recommended before proceeding with additional changes.
