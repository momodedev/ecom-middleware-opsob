#!/usr/bin/env python3
"""
Rocky Direct vs OBProxy Performance Comparison
Compares d8s_v5_rocky_direct.csv vs d8s_v5_rocky_obproxy.csv
"""

import csv
import sys
from pathlib import Path

DIRECT_CSV  = Path(__file__).parent / "d8s_v5_rocky_direct.csv"
PROXY_CSV   = Path(__file__).parent / "d8s_v5_rocky_obproxy.csv"
REPORT_MD   = Path(__file__).parent / "DIRECT_VS_PROXY_COMPARISON.md"

WORKLOADS = ["oltp_read_only", "oltp_write_only", "oltp_read_write"]
THREADS   = [16, 32, 64, 128, 256]


def load_csv(path):
    data = {}
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            key = (row["workload"], int(row["threads"]))
            data[key] = row
    return data


def fmt_float(v):
    try:
        return f"{float(v):.2f}"
    except (ValueError, TypeError):
        return "N/A"


def pct_diff(a, b):
    """Return (b-a)/a * 100 as a signed float, or None if either is zero/missing."""
    try:
        fa, fb = float(a), float(b)
        if fa == 0:
            return None
        return (fb - fa) / fa * 100
    except (ValueError, TypeError):
        return None


def arrow(pct, higher_is_better=True):
    if pct is None:
        return "N/A"
    if higher_is_better:
        return f"+{pct:.1f}%" if pct >= 0 else f"{pct:.1f}%"
    else:
        return f"+{pct:.1f}%" if pct >= 0 else f"{pct:.1f}%"


def run():
    if not DIRECT_CSV.exists():
        sys.exit(f"ERROR: {DIRECT_CSV} not found")
    if not PROXY_CSV.exists():
        sys.exit(f"ERROR: {PROXY_CSV} not found")

    direct = load_csv(DIRECT_CSV)
    proxy  = load_csv(PROXY_CSV)

    lines = []
    lines.append("# Rocky Direct vs OBProxy Performance Comparison")
    lines.append("")
    lines.append("**Date:** 2026-04-01  ")
    lines.append("**Cluster:** 3-node Rocky Linux OceanBase (D8s_v6)  ")
    lines.append("**Direct path:** 172.17.1.7:2881 (OceanBase native)  ")
    lines.append("**Proxy path:**  172.17.1.7:2883 (OBProxy)  ")
    lines.append("**Dataset:** 10 tables × 100,000 rows (sbtest)  ")
    lines.append("**Duration per test:** 120 s  ")
    lines.append("")

    summary_deltas = {"tps": [], "p95": []}

    for workload in WORKLOADS:
        lines.append(f"## {workload}")
        lines.append("")
        lines.append("| Threads | Direct TPS | Proxy TPS | TPS Δ | Direct P95 (ms) | Proxy P95 (ms) | P95 Δ | Both Status |")
        lines.append("|--------:|-----------:|----------:|------:|----------------:|---------------:|------:|-------------|")

        for t in THREADS:
            key = (workload, t)
            dr = direct.get(key)
            pr = proxy.get(key)

            dtps   = dr["tps"]   if dr else "—"
            ptps   = pr["tps"]   if pr else "—"
            dp95   = dr["p95_latency"] if dr else "—"
            pp95   = pr["p95_latency"] if pr else "—"
            dstat  = dr["status"] if dr else "missing"
            pstat  = pr["status"] if pr else "missing"
            both   = "ok" if dstat == "ok" and pstat == "ok" else f"D:{dstat}/P:{pstat}"

            tps_d = pct_diff(dtps, ptps)
            p95_d = pct_diff(dp95, pp95)

            if tps_d is not None:
                summary_deltas["tps"].append(tps_d)
            if p95_d is not None:
                summary_deltas["p95"].append(p95_d)

            lines.append(
                f"| {t:7d} | {fmt_float(dtps):>10} | {fmt_float(ptps):>9} | {arrow(tps_d):>5} "
                f"| {fmt_float(dp95):>15} | {fmt_float(pp95):>14} | {arrow(p95_d, higher_is_better=False):>5} "
                f"| {both} |"
            )

        lines.append("")

    # Summary
    lines.append("## Summary")
    lines.append("")
    if summary_deltas["tps"]:
        avg_tps_delta = sum(summary_deltas["tps"]) / len(summary_deltas["tps"])
        avg_p95_delta = sum(summary_deltas["p95"]) / len(summary_deltas["p95"]) if summary_deltas["p95"] else 0
        lines.append(f"| Metric | Avg Proxy vs Direct |")
        lines.append(f"|--------|---------------------|")
        lines.append(f"| TPS    | {avg_tps_delta:+.1f}%             |")
        lines.append(f"| P95    | {avg_p95_delta:+.1f}%             |")
        lines.append("")
        lines.append("### Interpretation")
        lines.append("")
        if -5 <= avg_tps_delta <= 5:
            lines.append("OBProxy introduces **negligible overhead** (<5% TPS impact). "
                         "Proxy-layer deployments are viable without significant performance penalty.")
        elif avg_tps_delta < -5:
            lines.append(f"OBProxy introduces a **{abs(avg_tps_delta):.1f}% average TPS reduction**. "
                         "Review OBProxy configuration (thread model, connection pool, cpu_quota_concurrency) "
                         "if proxy overhead is a concern.")
        else:
            lines.append(f"OBProxy shows **{avg_tps_delta:.1f}% TPS improvement** over direct connections, "
                         "likely due to connection pooling benefits at higher concurrency.")
    else:
        lines.append("_No comparable data points available (check CSV status columns)._")

    lines.append("")
    lines.append("---")
    lines.append("_Generated by compare_direct_vs_proxy.py_")

    report = "\n".join(lines) + "\n"
    REPORT_MD.write_text(report, encoding="utf-8")
    print(f"Report written to {REPORT_MD}")
    print()
    # Also print the summary section
    in_summary = False
    for line in lines:
        if line.startswith("## Summary"):
            in_summary = True
        if in_summary:
            print(line)


if __name__ == "__main__":
    run()
