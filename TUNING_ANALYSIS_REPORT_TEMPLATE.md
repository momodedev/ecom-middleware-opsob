# OceanBase v4.5.0 Performance Tuning Analysis Report

**Generated**: 2026-04-17
**Instance**: vm-ob-standalone (13.83.163.165)
**Hardware**: Standard_D16s_v6 (16 vCPU, 62 GB RAM)
**OceanBase Version**: 4.5.0.0

---

## Executive Summary

Performance impact of applying 6 recommended tuning parameters to OceanBase Standalone v4.5.0:

| Metric | Baseline | Tuned | Change | % Improvement |
|--------|----------|-------|--------|---------------|
| **RO@20t TPS** | 776.02 | TBD | TBD | TBD |
| **RO@50t TPS** | 655.33 | TBD | TBD | TBD |
| **RO@100t TPS** | 839.16 | TBD | TBD | TBD |
| **RO@200t TPS** | 1007.99 | TBD | TBD | TBD |
| **RW@20t TPS** | 991.71 | TBD | TBD | TBD |
| **RW@50t TPS** | 907.08 | TBD | TBD | TBD |
| **RW@100t TPS** | 782.08 | TBD | TBD | TBD |
| **RW@200t TPS** | 670.57 | TBD | TBD | TBD |

---

## Applied Tuning Parameters

### Successfully Applied (6/7)

| # | Parameter | Before | After | Impact |
|---|-----------|--------|-------|--------|
| 1 | `enable_adaptive_plan_cache` | False | **True** | ✅ Adaptive plan selection enabled |
| 2 | `freeze_trigger_percentage` | 20% | **15%** | ✅ MemStore flush at 15% (earlier) - reduces write stall |
| 3 | `ob_enable_batched_multi_statement` | False | **True** | ✅ Batch DML enabled - improves bulk write throughput |
| 4 | `compaction_high_thread_score` | 0 (auto) | **4** | ✅ Reserved 4 threads for compaction - isolates from OLTP |
| 5 | `net_thread_count` | 0 (auto) | **8** | ✅ 8 network threads - explicit tuning |
| 6 | `cpu_quota_concurrency` | 10 | **12** | ✅ 168 max concurrency (14 CPU × 12) |

### Failed to Apply (1/7)

| # | Parameter | Issue | Reason |
|---|-----------|-------|--------|
| 7 | `use_large_pages` | ERROR 4147 | Requires OS-level hugepages configuration; dynamic change not supported |

---

## Baseline Results (Before Tuning)

**Configuration**: Default parameters
**Run Date**: 2026-04-16 15:26 UTC
**Test Duration**: 300s per case + 120s warmup

### oltp_read_only (RO)

| Threads | TPS | P95 Latency (ms) | Avg Latency (ms) | Total Queries | Note |
|---------|-----|------------------|------------------|---------------|------|
| **20** | 776.02 | 47.47 | 25.77 | 3,725,200 | Baseline - low concurrency |
| **50** | 655.33 | 153.02 | 76.29 | 3,146,096 | Latency increases, throughput drops |
| **100** | 839.16 | 150.29 | 119.15 | 4,029,152 | TPS recovers, latency climbs |
| **200** | 1007.99 | 257.95 | 198.32 | 4,841,264 | Peak TPS (1K), high latency = saturation |

**oltp_read_only Observations**:
- **Peak throughput**: ~1,008 TPS @ 200 threads
- **Latency cliff**: 50→100 threads shows 2x latency increase
- **Saturation point**: Evident at 200 threads (p95 = 258ms)
- **Concurrency sweet spot**: 20-50 threads for low latency

### oltp_read_write (RW)

| Threads | TPS | P95 Latency (ms) | Avg Latency (ms) | Total Queries | Note |
|---------|-----|------------------|------------------|---------------|---|
| **20** | 991.71 | 31.37 | 20.17 | 5,950,600 | Baseline - write workload performs well |
| **50** | 907.08 | 87.56 | 55.10 | 5,445,800 | Slight drop in TPS |
| **100** | 782.08 | 200.47 | 127.85 | 4,693,620 | Significant drop with 100 threads |
| **200** | 670.57 | 475.79 | 298.18 | 4,025,780 | Severe contention; p95 = 476ms |

**oltp_read_write Observations**:
- **Peak throughput**: ~992 TPS @ 20 threads (write-friendly)
- **Write contention**: TPS drops 32% from 20→200 threads
- **P95 latency worst**: 476ms @ 200 threads (indicates lock contention)
- **MemStore flush**: Likely triggered during high write load (freeze_trigger_percentage=20%)

---

## Tuning Rationale

### 1. `enable_adaptive_plan_cache = True`
- **Why**: Allows optimizer to dynamically select between cached and custom plans based on data distribution
- **Expected Effect**: Better query performance under varying data patterns; reduces plan cache misses
- **Measurable Impact**: Potential 5-10% improvement in query latency

### 2. `freeze_trigger_percentage = 15%` (from 20%)
- **Why**: MemStore flushes to disk at 15% of memory_limit (≈7.5 GB instead of 10 GB)
- **Expected Effect**: More frequent, smaller MemStore flushes; reduces write latency spikes
- **Trade-off**: Slightly more I/O, but better write latency consistency
- **Measurable Impact**: Expected 10-15% improvement in write latency (p99/p95)

### 3. `ob_enable_batched_multi_statement = True`
- **Why**: Batches multiple INSERT/UPDATE statements into single transaction
- **Expected Effect**: Better throughput for bulk DML operations
- **Measurable Impact**: 5-15% improvement in write-heavy workloads (RW)

### 4. `compaction_high_thread_score = 4` (from 0 auto)
- **Why**: Reserves 4 threads for high-priority compaction to prevent CPU stealing from OLTP
- **Expected Effect**: More predictable OLTP latency during compaction
- **Measurable Impact**: Smoother performance curve under varying compaction load

### 5. `net_thread_count = 8` (from 0 auto)
- **Why**: Explicit network thread pool sizing for high-concurrency workloads
- **Expected Effect**: Better RPC throughput and reduced context switching
- **Measurable Impact**: 3-8% improvement for concurrent workloads (100+threads)

### 6. `cpu_quota_concurrency = 12` (from 10)
- **Why**: 14 CPUs × 12 = 168 max concurrent requests (up from 140)
- **Expected Effect**: Better CPU utilization at 100-200 thread concurrency
- **Measurable Impact**: 5-10% throughput improvement at high concurrency

---

## Tuned Results (After Tuning)

**Configuration**: 6 Tuning parameters applied
**Run Date**: 2026-04-17 06:03 UTC
**Test Duration**: 300s per case + 120s warmup

### oltp_read_only (RO) - TUNED

| Threads | TPS | P95 Latency (ms) | Avg Latency (ms) | Total Queries | vs Baseline |
|---------|-----|------------------|------------------|---------------|------------|
| **20** | TBD | TBD | TBD | TBD | TBD |
| **50** | TBD | TBD | TBD | TBD | TBD |
| **100** | TBD | TBD | TBD | TBD | TBD |
| **200** | TBD | TBD | TBD | TBD | TBD |

### oltp_read_write (RW) - TUNED

| Threads | TPS | P95 Latency (ms) | Avg Latency (ms) | Total Queries | vs Baseline |
|---------|-----|------------------|------------------|---------------|------------|
| **20** | TBD | TBD | TBD | TBD | TBD |
| **50** | TBD | TBD | TBD | TBD | TBD |
| **100** | TBD | TBD | TBD | TBD | TBD |
| **200** | TBD | TBD | TBD | TBD | TBD |

---

## Performance Analysis (To be completed after tuned run)

### Key Improvements Expected

1. **Write Performance (RW)**
   - Reduced MemStore flush wait time (freeze_trigger at 15% vs 20%)
   - Better batch operation support
   - Expected: **15-25% improvement** in RW @ 100-200 threads

2. **Read Performance (RO)**
   - Adaptive plan selection
   - Better CPU utilization (net threads + concurrency)
   - Expected: **5-10% improvement** in RO @ 100-200 threads

3. **Latency Distribution**
   - Lower P95/P99 latencies due to frequent MemStore flushes
   - Smoother saturation curve (less cliff-drop between thread levels)
   - Expected: **20-30% improvement** in P95 latency @ 100-200 threads

4. **Scalability**
   - Linear improvement from 20→100 threads
   - Better scaling to 200 threads (less degradation)

---

## Recommendations & Next Steps

### If Tuned Performance is Positive (+5-10%+):
1. ✅ **Keep all tuning parameters** — persist in `/home/admin/ob-standalone.yaml`
2. ✅ **Update OBD YAML configuration** for future deployments
3. ✅ **Document as default for production** OceanBase 4.5.0 deployments
4. **Consider additional tuning**:
   - Enable `use_large_pages = true` after OS-level hugepages setup
   - Test `cpu_quota_concurrency = 14-16` for even higher ceiling
   - Profile CPU/memory during 200-thread workload

### If Tuned Performance is Neutral or Negative (<5% change):
1. Revert and investigate which parameter caused issues (binary search)
2. Consider hardware-specific tuning (network topology, NUMA effects)
3. Run longer baseline (1h each case) to capture compaction effects

### Operational Insights from Baseline:
- **Current sweet spot**: 50-100 threads for balanced latency/throughput
- **Saturation point**: Visible at 200 threads (latency > 250ms p95)
- **Read vs Write**: Write workload (RW) scales better at low concurrency (20t: RW=992 TPS vs RO=776 TPS)
- **Lock contention**: Severe write lock contention at 200 threads (RW p95 = 476ms)
