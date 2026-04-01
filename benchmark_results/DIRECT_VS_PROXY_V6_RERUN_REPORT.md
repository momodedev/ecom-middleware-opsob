# Rocky V6 Direct vs OBProxy Comparison (Latest Rerun)

- Direct baseline: `d8s_v6_rocky_direct_nmysql_latest.csv`
- Proxy rerun: `d8s_v6_rocky_obproxy_full_rerun.csv`
- Compared workloads: `oltp_read_only`, `oltp_read_write` (common matrix)
- Threads: `20, 50, 100, 200`

## oltp_read_only

| Threads | Direct TPS | Proxy TPS | TPS Delta | Direct P95 ms | Proxy P95 ms | P95 Delta |
|---:|---:|---:|---:|---:|---:|---:|
| 20 | 1527.46 | 3862.84 | +152.9% | 18.95 | 5.99 | -68.4% |
| 50 | 2010.26 | 5732.87 | +185.2% | 31.37 | 11.87 | -62.2% |
| 100 | 2009.15 | 6431.98 | +220.1% | 56.84 | 26.20 | -53.9% |
| 200 | 2006.45 | 6695.84 | +233.7% | 108.68 | 63.32 | -41.7% |

## oltp_read_write

| Threads | Direct TPS | Proxy TPS | TPS Delta | Direct P95 ms | Proxy P95 ms | P95 Delta |
|---:|---:|---:|---:|---:|---:|---:|
| 20 | 824.35 | 1288.32 | +56.3% | 30.81 | 20.00 | -35.1% |
| 50 | 1189.71 | 2153.35 | +81.0% | 51.94 | 29.72 | -42.8% |
| 100 | 1216.98 | 2117.46 | +74.0% | 92.42 | 58.92 | -36.2% |
| 200 | 1178.85 | 2646.28 | +124.5% | 189.93 | 125.52 | -33.9% |

## oltp_write_only (Proxy-Only In This Pair)

| Threads | Proxy TPS | Proxy P95 ms |
|---:|---:|---:|
| 20 | 2335.40 | 10.27 |
| 50 | 4890.03 | 12.52 |
| 100 | 6435.04 | 19.29 |
| 200 | 7131.97 | 40.37 |

## Summary (Common RO/RW Cases)

| Metric | Avg Proxy vs Direct |
|---|---:|
| TPS | +141.0% |
| P95 | -46.8% |

