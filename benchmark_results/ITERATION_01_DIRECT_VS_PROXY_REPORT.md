# Iteration-01 Direct vs OBProxy Comparison

- Direct baseline: d8s_v6_rocky_direct_nmysql_latest.csv
- Iteration-01 proxy CSV: 20260401T150634Z_d8s_v6_rocky_obproxy_iter01.csv
- Compared workloads: oltp_read_only, oltp_read_write
- Threads: 20, 50, 100, 200

## oltp_read_only

| Threads | Direct TPS | Proxy TPS | TPS Delta | Direct P95 ms | Proxy P95 ms | P95 Delta |
|---:|---:|---:|---:|---:|---:|---:|
| 20 | 1527.46 | 3768.54 | +146.7% | 18.95 | 6.32 | -66.6% |
| 50 | 2010.26 | 5437.85 | +170.5% | 31.37 | 12.75 | -59.4% |
| 100 | 2009.15 | 6113.08 | +204.3% | 56.84 | 27.17 | -52.2% |
| 200 | 2006.45 | 6406.09 | +219.3% | 108.68 | 62.19 | -42.8% |

## oltp_read_write

| Threads | Direct TPS | Proxy TPS | TPS Delta | Direct P95 ms | Proxy P95 ms | P95 Delta |
|---:|---:|---:|---:|---:|---:|---:|
| 20 | 824.35 | 1131.81 | +37.3% | 30.81 | 20.37 | -33.9% |
| 50 | 1189.71 | 2146.72 | +80.4% | 51.94 | 29.72 | -42.8% |
| 100 | 1216.98 | 2189.54 | +79.9% | 92.42 | 58.92 | -36.2% |
| 200 | 1178.85 | 2673.02 | +126.7% | 189.93 | 142.39 | -25.0% |

## oltp_write_only (Proxy-Only In This Comparison)

| Threads | Proxy TPS | Proxy P95 ms |
|---:|---:|---:|
| 20 | 2443.41 | 10.09 |
| 50 | 4378.30 | 14.46 |
| 100 | 5652.10 | 22.28 |
| 200 | 7034.24 | 40.37 |

## Summary (RO+RW Common Cases)

| Metric | Avg Proxy vs Direct |
|---|---:|
| TPS | +133.1% |
| P95 | -44.9% |

