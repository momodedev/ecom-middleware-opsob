# OceanBase Rocky v9.7 V6 Cluster Audit

- Audit timestamp (UTC): 2026-04-02T03:12:46Z
- Cluster type: OceanBase SQL cluster on Rocky Linux 9.7 VMs
- Control node: 20.245.23.176
- Observer nodes: 172.17.1.5, 172.17.1.6, 172.17.1.7

## Scope

- System-level checks: OceanBase server/tenant/zone status, key parameters, tenant runtime variables, tenant resource units.
- OS-level checks: OS/kernel, CPU/memory/disk layout, THP/swap/sysctl/limits, observer+obproxy process and listener ports.

## PASS/FAIL Checklist

## System-Level Checklist

| Item | Result | Evidence | Notes |
|---|---|---|---|
| All observer servers ACTIVE | PASS | 172.17.1.5 zone3 ACTIVE; 172.17.1.6 zone2 ACTIVE; 172.17.1.7 zone1 ACTIVE | Runtime server health is normal. |
| All zones ACTIVE | PASS | zone1 ACTIVE, zone2 ACTIVE, zone3 ACTIVE | Multi-zone deployment healthy. |
| Key tenants in NORMAL state | PASS | sys NORMAL, sbtest_tenant NORMAL, META$1002 NORMAL | Tenant runtime is healthy. |
| sbtest_tenant locality across 3 zones | PASS | FULL{1}@zone1, FULL{1}@zone2, FULL{1}@zone3 | Good HA layout. |
| sbtest_tenant unit resources consistent by zone | PASS | zone1/2/3 each: min_cpu=6, max_cpu=6, memory_size=25769803776 (24 GiB) | Resource sizing is uniform. |
| Tenant SQL runtime variables present | PASS | ob_trx_timeout=100000000; ob_trx_lock_timeout=10000000; ob_query_timeout=1000000000; ob_sql_work_area_percentage=20 | Variables are queryable and set. |
| System parameters: memory_limit_percentage=80 | PASS | 80 on all 3 nodes | Consistent. |
| System parameters: SQL audit enabled | PASS | enable_sql_audit=True on all 3 nodes | Audit enabled cluster-wide. |
| System parameters: syslog recycle enabled | PASS | enable_syslog_recycle=True on all 3 nodes | Log management enabled. |
| System parameters: syslog level configured | PASS | syslog_level=WDIAG on all 3 nodes | Consistent. |
| cpu_quota_concurrency single effective value visibility | FAIL | GV$OB_PARAMETERS shows 10, 4, and 2 per node | Multiple scoped rows are present; effective runtime scope should be validated explicitly before tuning. |
| OBD management metadata available on control node | FAIL | obd not found; ~/.obd/cluster/ob_cluster/config.yaml not found on 20.245.23.176 | Runtime cluster is healthy, but control-node OBD artifacts are missing here. |

## OS-Level Checklist

| Item | Result | Evidence | Notes |
|---|---|---|---|
| OS distribution/version consistent across nodes | PASS | Rocky Linux 9.7 on 172.17.1.5/.6/.7 | Aligned platform baseline. |
| Kernel version consistent | PASS | 5.14.0-611.41.1.el9_7.x86_64 on all nodes | Aligned kernel baseline. |
| CPU topology consistent | PASS | 8 vCPU, 1 socket, 4 cores/socket, 2 threads/core, NUMA nodes=1 | Uniform node shape. |
| Data/redo dedicated disks mounted | PASS | /oceanbase/data on nvme0n2 (500G), /oceanbase/redo on nvme0n3 (500G) | Proper OB storage split. |
| Swap disabled | PASS | Swap 0B on all 3 nodes | Expected for DB workload. |
| THP disabled | PASS | /sys/.../enabled and defrag show [never] | Good for latency consistency. |
| vm.swappiness=0 | PASS | vm.swappiness = 0 on all nodes | Suitable for DB workloads. |
| net.core.somaxconn configured | PASS | 2048 on all nodes | Acceptable listener backlog baseline. |
| File descriptor limit high enough | PASS | ulimit -n = 655350 | Adequate headroom for connections/files. |
| observer process running on each node | PASS | observer present on all nodes | Service up cluster-wide. |
| obproxy process running on each node | PASS | obproxy present on all nodes | Proxy layer available cluster-wide. |
| Required ports listening (2881/2882/2883/2884) | PASS | ss -lntp confirms listeners on each node | Data path and proxy path are open. |
| Memory headroom under sustained load | FAIL | Available memory observed ~1.1-1.6 GiB on 31 GiB nodes | High memory pressure risk during peak benchmark/tuning iterations. |

## Risk Summary

- High priority: low available memory on all observer nodes under active load.
- Medium priority: cpu_quota_concurrency appears with multiple scoped values in GV$OB_PARAMETERS; effective value should be validated before iterative tuning.
- Medium priority: missing OBD management artifacts on the checked control node can complicate some cluster-management workflows.

## Recommended Follow-ups

1. Validate effective cpu_quota_concurrency scope and active value using scoped queries and runtime verification.
2. Track memory pressure during benchmark loops and tune tenant/query memory behavior conservatively.
3. If needed for operations, install/restore OBD management tools and cluster metadata on the control node.
