#!/usr/bin/env python3
"""
Merge read-only CSVs (existing) with new write/RW CSVs, then regenerate
DIRECT_VS_PROXY_COMPARISON.md.

Usage:
    python merge_and_compare.py
"""

import csv
import sys
from pathlib import Path

BASE = Path(__file__).parent

# Input files
DIRECT_RO   = BASE / "d8s_v5_rocky_direct.csv"        # existing read-only data
PROXY_RO    = BASE / "d8s_v5_rocky_obproxy.csv"        # existing read-only data
DIRECT_RW   = BASE / "d8s_v5_rocky_direct_rw.csv"      # new write+RW data
PROXY_RW    = BASE / "d8s_v5_rocky_obproxy_rw.csv"     # new write+RW data

# Output: merged full CSVs
DIRECT_FULL = BASE / "d8s_v5_rocky_direct_full.csv"
PROXY_FULL  = BASE / "d8s_v5_rocky_obproxy_full.csv"
REPORT_MD   = BASE / "DIRECT_VS_PROXY_COMPARISON.md"

WORKLOADS = ["oltp_read_only", "oltp_write_only", "oltp_read_write"]
THREADS   = [16, 32, 64, 128, 256]
FIELDS    = ["timestamp", "label", "workload", "threads", "tps", "p95_latency",
             "avg_latency", "total_queries", "errors", "rc", "status",
             "cpu_pct", "mem_pct", "disk_io_mbps"]


def load_csv(path):
    if not path.exists():
        return {}
    rows = {}
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            key = (row["workload"], int(row["threads"]))
            rows[key] = row
    return rows


def merge(ro_path, rw_path, out_path, label):
    ro = load_csv(ro_path)
    rw = load_csv(rw_path)
    merged = {**ro, **rw}          # rw rows override any empty ro entries for write workloads
    if not merged:
        print(f"WARNING: no data for {label}")
        return {}
    with open(out_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        for wl in WORKLOADS:
            for t in THREADS:
                row = merged.get((wl, t))
                if row:
                    w.writerow({k: row.get(k, "") for k in FIELDS})
    print(f"Merged {label} -> {out_path} ({len(merged)} rows)")
    return merged


def fmt(v):
    try:
        return f"{float(v):.2f}"
    except (ValueError, TypeError):
        return "N/A"


def pct_diff(a, b):
    try:
        fa, fb = float(a), float(b)
        if fa == 0:
            return None
        return (fb - fa) / fa * 100
    except (ValueError, TypeError):
        return None


def run():
    # Check which rw files are present
    has_direct_rw = DIRECT_RW.exists()
    has_proxy_rw  = PROXY_RW.exists()

    if not has_direct_rw and not has_proxy_rw:
        sys.exit("ERROR: Neither _rw.csv file found. Run benchmark_rocky_writes.sh first.")
    if not has_direct_rw:
        print(f"WARNING: {DIRECT_RW} missing – using existing direct CSV only")
    if not has_proxy_rw:
        print(f"WARNING: {PROXY_RW} missing – using existing proxy CSV only")

    direct_data = merge(DIRECT_RO, DIRECT_RW if has_direct_rw else Path("/nonexistent"), DIRECT_FULL, "direct")
    proxy_data  = merge(PROXY_RO,  PROXY_RW  if has_proxy_rw  else Path("/nonexistent"), PROXY_FULL,  "proxy")

    # Re-load merged for the report
    direct = load_csv(DIRECT_FULL)
    proxy  = load_csv(PROXY_FULL)

    lines = []
    lines += [
        "# Rocky Direct vs OBProxy — Full Performance Comparison",
        "",
        "**Date:** 2026-04-01  ",
        "**Cluster:** 3-node Rocky Linux OceanBase (D8s_v6)  ",
        "**Direct path:** 172.17.1.7:2881 (OceanBase native)  ",
        "**Proxy path:**  172.17.1.7:2883 (OBProxy)  ",
        "**Dataset:** 10 tables × 100,000 rows (sbtest), 120 s per test  ",
        "**OB session overrides:** ob_trx_timeout=100s, ob_trx_lock_timeout=10s  ",
        "",
    ]

    all_tps_deltas = []
    all_p95_deltas = []

    for workload in WORKLOADS:
        lines.append(f"## {workload}")
        lines.append("")
        lines.append("| Threads | Direct TPS | Proxy TPS | TPS Δ | Direct P95 ms | Proxy P95 ms | P95 Δ | Status (D/P) |")
        lines.append("|--------:|-----------:|----------:|------:|--------------:|-------------:|------:|:-------------|")
        for t in THREADS:
            key = (workload, t)
            dr = direct.get(key)
            pr = proxy.get(key)
            dtps = dr["tps"] if dr else "—"
            ptps = pr["tps"] if pr else "—"
            dp95 = dr["p95_latency"] if dr else "—"
            pp95 = pr["p95_latency"] if pr else "—"
            dst  = dr["status"] if dr else "missing"
            pst  = pr["status"] if pr else "missing"
            both = "ok/ok" if dst == "ok" and pst == "ok" else f"{dst}/{pst}"

            td = pct_diff(dtps, ptps)
            pd = pct_diff(dp95, pp95)
            if td is not None: all_tps_deltas.append(td)
            if pd is not None: all_p95_deltas.append(pd)

            def arrow(d):
                if d is None: return "N/A"
                return f"{d:+.1f}%"

            lines.append(
                f"| {t:7d} | {fmt(dtps):>10} | {fmt(ptps):>9} | {arrow(td):>6} "
                f"| {fmt(dp95):>13} | {fmt(pp95):>12} | {arrow(pd):>6} | {both} |"
            )
        lines.append("")

    lines.append("## Overall Summary")
    lines.append("")
    if all_tps_deltas:
        avg_tps = sum(all_tps_deltas) / len(all_tps_deltas)
        avg_p95 = sum(all_p95_deltas) / len(all_p95_deltas) if all_p95_deltas else 0
        lines += [
            f"| Metric | Avg Proxy vs Direct ({len(all_tps_deltas)} data points) |",
            "|--------|------|",
            f"| TPS    | {avg_tps:+.1f}% |",
            f"| P95    | {avg_p95:+.1f}% |",
            "",
            "### Interpretation",
            "",
        ]
        if -5 <= avg_tps <= 5:
            lines.append("OBProxy introduces **negligible overhead** (<5% TPS impact). Proxy deployments are viable.")
        elif avg_tps < -5:
            lines.append(f"OBProxy introduces a **{abs(avg_tps):.1f}% average TPS reduction**. "
                         "Consider tuning OBProxy thread model and connection pool.")
        else:
            lines.append(f"OBProxy shows **{avg_tps:.1f}% average TPS improvement** over direct connections "
                         "(connection pooling benefit).")
    else:
        lines.append("_No comparable data points._")

    lines += ["", "---", "_Generated by merge_and_compare.py_", ""]
    REPORT_MD.write_text("\n".join(lines), encoding="utf-8")
    print(f"\nReport: {REPORT_MD}")
    # Print summary to stdout
    for line in lines[-20:]:
        print(line)


if __name__ == "__main__":
    run()
