# Rocky OceanBase Performance Comparison Report

## Executive Summary

**Objective**: Evaluate performance improvements from Rocky cluster reconfiguration

**Baseline**: d8s_v6.csv (pre-reconfiguration)
**Comparison**: d8s_v5_rocky_direct.csv (post-reconfiguration, direct connection)

**Reconfiguration Applied**:
- Tenant locality distribution: FULL{1}@zone1, FULL{1}@zone2, FULL{1}@zone3
- Table partitioning: sbtest1 hash-partitioned into 1024 partitions
- Transaction tuning: ob_trx_timeout=1000000000, ob_trx_lock_timeout=10000, ob_early_lock_release=ON
- Worker tuning: workers_per_cpu_quota=10, px_workers_per_cpu_quota=10, cpu_quota_concurrency=10

---

## Performance Metrics Comparison

### Read-Only Workload (oltp_read_only)

| Threads | Baseline TPS | Post-Config TPS | Delta | % Change | Baseline P95 (ms) | Post-Config P95 (ms) |
|---------|-------------|-----------------|-------|----------|-------------------|---------------------|
| 16      | -           | -               | -     | -         | -                 | -                   |
| 32      | -           | -               | -     | -         | -                 | -                   |
| 64      | -           | -               | -     | -         | -                 | -                   |
| 128     | -           | -               | -     | -         | -                 | -                   |
| 256     | -           | -               | -     | -         | -                 | -                   |

**Analysis**: TBD after benchmark completion

---

### Write-Only Workload (oltp_write_only)

| Threads | Baseline TPS | Post-Config TPS | Delta | % Change | Baseline P95 (ms) | Post-Config P95 (ms) |
|---------|-------------|-----------------|-------|----------|-------------------|---------------------|
| 16      | -           | -               | -     | -         | -                 | -                   |
| 32      | -           | -               | -     | -         | -                 | -                   |
| 64      | -           | -               | -     | -         | -                 | -                   |
| 128     | -           | -               | -     | -         | -                 | -                   |
| 256     | -           | -               | -     | -         | -                 | -                   |

**Analysis**: TBD after benchmark completion

---

### Read-Write Mixed Workload (oltp_read_write)

| Threads | Baseline TPS | Post-Config TPS | Delta | % Change | Baseline P95 (ms) | Post-Config P95 (ms) |
|---------|-------------|-----------------|-------|----------|-------------------|---------------------|
| 16      | -           | -               | -     | -         | -                 | -                   |
| 32      | -           | -               | -     | -         | -                 | -                   |
| 64      | -           | -               | -     | -         | -                 | -                   |
| 128     | -           | -               | -     | -         | -                 | -                   |
| 256     | -           | -               | -     | -         | -                 | -                   |

**Analysis**: TBD after benchmark completion

---

## Key Findings

### Throughput Improvements
- **Best case**: TBD
- **Worst case**: TBD
- **Average improvement**: TBD %

### Latency Impact
- **P95 latency change**: TBD
- **How contention-sensitive is the workload**: TBD

### Scalability
- **Linear scaling up to**: TBD threads
- **Saturation point**: TBD threads
- **Max throughput achieved**: TBD TPS

---

## Observations

### Pre-Reconfiguration Challenges (d8s_v6.csv)
- High lock contention at 128+ threads
- Write-only workload failures (error code 6002 - transaction rollback)
- Limited partition concurrency

### Post-Reconfiguration Improvements (d8s_v5_rocky_direct.csv)
- Enhanced partition distribution enabling better concurrency
- Improved transaction timeout handling
- Better resource allocation across zones

---

## Conclusion

TBD: Summary of performance gains and recommendations for further tuning

---

## Data Files

- **Baseline CSV**: `/tmp/oceanbase-bench/d8s_v6.csv`
- **Comparison CSV**: `/tmp/oceanbase-bench/d8s_v5_rocky_direct.csv`
- **Generated**: $(date)
