#!/usr/bin/env python3
"""Generate automatic benchmark analysis report from a CSV file.

Outputs:
1. Whether cpu_pct/mem_pct/disk_io_mbps contain zero values.
2. Knee thread per workload (thread with max TPS, plus first degradation point).
3. RW P95 alert if any row exceeds threshold.
"""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path


def to_float(value: str, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def to_int(value: str, default: int = 0) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def load_rows(csv_path: Path) -> list[dict]:
    rows: list[dict] = []
    with csv_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for raw in reader:
            row = dict(raw)
            row["threads"] = to_int(raw.get("threads", "0"))
            row["tps"] = to_float(raw.get("tps", "0"))
            row["p95_latency"] = to_float(raw.get("p95_latency", "0"))
            row["avg_latency"] = to_float(raw.get("avg_latency", "0"))
            row["cpu_pct"] = to_float(raw.get("cpu_pct", "0"))
            row["mem_pct"] = to_float(raw.get("mem_pct", "0"))
            row["disk_io_mbps"] = to_float(raw.get("disk_io_mbps", "0"))
            rows.append(row)
    return rows


def zero_metric_rows(rows: list[dict]) -> list[dict]:
    bad = []
    for r in rows:
        if r["cpu_pct"] == 0.0 or r["mem_pct"] == 0.0 or r["disk_io_mbps"] == 0.0:
            bad.append(r)
    return bad


def workload_knee(rows: list[dict], workload: str) -> tuple[int, float, int | None]:
    subset = sorted((r for r in rows if r.get("workload") == workload), key=lambda x: x["threads"])
    if not subset:
        return 0, 0.0, None

    max_row = max(subset, key=lambda x: x["tps"])
    first_drop: int | None = None
    prev_tps: float | None = None
    for r in subset:
        if prev_tps is not None and r["tps"] < prev_tps:
            first_drop = r["threads"]
            break
        prev_tps = r["tps"]

    return int(max_row["threads"]), float(max_row["tps"]), first_drop


def rw_p95_alerts(rows: list[dict], threshold_ms: float) -> list[dict]:
    alerts = []
    for r in rows:
        if r.get("workload") == "oltp_read_write" and r["p95_latency"] > threshold_ms:
            alerts.append(r)
    return sorted(alerts, key=lambda x: x["threads"])


def avg(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def build_report(rows: list[dict], csv_name: str, rw_p95_threshold: float) -> str:
    lines: list[str] = []
    lines.append("================ Auto Benchmark Report ================")
    lines.append(f"source_csv={csv_name}")
    lines.append(f"rows={len(rows)}")

    bad_rows = zero_metric_rows(rows)
    lines.append("[1] Host Metrics Zero-Value Check")
    lines.append(
        f"zero_metric_rows={len(bad_rows)}"
    )
    if bad_rows:
        for r in bad_rows:
            lines.append(
                "  WARN row: "
                f"workload={r.get('workload','')},threads={r['threads']},"
                f"cpu_pct={r['cpu_pct']:.1f},mem_pct={r['mem_pct']:.1f},disk_io_mbps={r['disk_io_mbps']:.2f}"
            )
    else:
        lines.append("  OK: cpu_pct/mem_pct/disk_io_mbps are all non-zero")

    lines.append("[2] Knee Thread Per Workload")
    workloads = ["oltp_read_only", "oltp_write_only", "oltp_read_write"]
    for wl in workloads:
        knee_thread, knee_tps, first_drop = workload_knee(rows, wl)
        if knee_thread == 0:
            lines.append(f"  {wl}: no data")
            continue
        lines.append(
            f"  {wl}: knee_thread={knee_thread},knee_tps={knee_tps:.2f},"
            f"first_drop_thread={first_drop if first_drop is not None else 'none'}"
        )

    lines.append(f"[3] RW Degradation Alert (p95 > {rw_p95_threshold:.1f}ms)")
    alerts = rw_p95_alerts(rows, rw_p95_threshold)
    if not alerts:
        lines.append("  OK: no RW p95 alert rows")
    else:
        lines.append(f"  ALERT rows={len(alerts)}")
        for r in alerts:
            lines.append(
                f"  ALERT: threads={r['threads']},tps={r['tps']:.2f},p95={r['p95_latency']:.2f},avg={r['avg_latency']:.2f},"
                f"cpu_pct={r['cpu_pct']:.1f},disk_io_mbps={r['disk_io_mbps']:.2f}"
            )

    lines.append("[4] Workload Averages")
    by = defaultdict(list)
    for r in rows:
        by[r.get("workload", "")].append(r)
    for wl in workloads:
        s = by.get(wl, [])
        if not s:
            lines.append(f"  {wl}: no data")
            continue
        lines.append(
            f"  {wl}: avg_tps={avg([x['tps'] for x in s]):.2f},"
            f"avg_p95={avg([x['p95_latency'] for x in s]):.2f},"
            f"avg_cpu={avg([x['cpu_pct'] for x in s]):.1f},"
            f"avg_mem={avg([x['mem_pct'] for x in s]):.1f},"
            f"avg_disk={avg([x['disk_io_mbps'] for x in s]):.2f}"
        )

    lines.append("=======================================================")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Auto benchmark report for OceanBase sysbench CSV")
    parser.add_argument("--csv", required=True, help="Path to benchmark CSV")
    parser.add_argument("--output", default="", help="Optional output report file path")
    parser.add_argument("--rw-p95-threshold", type=float, default=200.0, help="RW p95 alert threshold in ms")
    args = parser.parse_args()

    csv_path = Path(args.csv)
    if not csv_path.exists():
        raise SystemExit(f"CSV not found: {csv_path}")

    rows = load_rows(csv_path)
    report = build_report(rows, csv_path.name, args.rw_p95_threshold)
    print(report, end="")

    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(report, encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
