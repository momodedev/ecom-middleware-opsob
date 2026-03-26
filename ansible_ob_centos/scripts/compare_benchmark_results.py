#!/usr/bin/env python3
import argparse
import csv
from collections import defaultdict


def parse_args():
    parser = argparse.ArgumentParser(description="Compare OceanBase benchmark CSV results (v6 vs v5)")
    parser.add_argument("--v6", required=True, help="CSV path for D8s_v6 results")
    parser.add_argument("--v5", required=True, help="CSV path for D8s_v5 results")
    parser.add_argument("--v6-hourly-cost", type=float, required=True, help="Hourly VM cost for D8s_v6")
    parser.add_argument("--v5-hourly-cost", type=float, required=True, help="Hourly VM cost for D8s_v5")
    return parser.parse_args()


def load_csv(path):
    grouped = defaultdict(list)
    with open(path, newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            key = (row["workload"], int(row["threads"]))
            grouped[key].append(
                {
                    "tps": float(row.get("tps", 0) or 0),
                    "p95_ms": float(row.get("p95_ms", 0) or 0),
                    "errors": float(row.get("errors", 0) or 0),
                }
            )

    summary = {}
    for key, rows in grouped.items():
        n = len(rows)
        tps_avg = sum(item["tps"] for item in rows) / n
        p95_avg = sum(item["p95_ms"] for item in rows) / n
        errors_avg = sum(item["errors"] for item in rows) / n
        summary[key] = {
            "samples": n,
            "tps_avg": tps_avg,
            "p95_avg": p95_avg,
            "errors_avg": errors_avg,
        }
    return summary


def pct_delta(new, old):
    if old == 0:
        return 0.0
    return ((new - old) / old) * 100.0


def cost_per_ktps(hourly_cost, tps):
    if tps <= 0:
        return 0.0
    return hourly_cost / (tps / 1000.0)


def print_table(headers, rows):
    widths = [len(str(h)) for h in headers]
    for row in rows:
        for idx, value in enumerate(row):
            widths[idx] = max(widths[idx], len(str(value)))

    def fmt_line(values):
        return " | ".join(str(v).ljust(widths[i]) for i, v in enumerate(values))

    print(fmt_line(headers))
    print("-+-".join("-" * w for w in widths))
    for row in rows:
        print(fmt_line(row))


def main():
    args = parse_args()
    v6 = load_csv(args.v6)
    v5 = load_csv(args.v5)

    keys = sorted(set(v6.keys()) & set(v5.keys()))
    if not keys:
        raise SystemExit("No overlapping workload+threads keys found between the two CSV files")

    perf_rows = []
    cost_rows = []

    for workload, threads in keys:
        s6 = v6[(workload, threads)]
        s5 = v5[(workload, threads)]

        tps_delta = pct_delta(s6["tps_avg"], s5["tps_avg"])
        p95_improve = pct_delta(s5["p95_avg"] - s6["p95_avg"], s5["p95_avg"]) if s5["p95_avg"] else 0.0

        perf_rows.append(
            [
                workload,
                threads,
                f"{s6['tps_avg']:.2f}",
                f"{s5['tps_avg']:.2f}",
                f"{tps_delta:+.2f}%",
                f"{s6['p95_avg']:.2f}",
                f"{s5['p95_avg']:.2f}",
                f"{p95_improve:+.2f}%",
                f"{s6['errors_avg']:.2f}",
                f"{s5['errors_avg']:.2f}",
            ]
        )

        c6 = cost_per_ktps(args.v6_hourly_cost, s6["tps_avg"])
        c5 = cost_per_ktps(args.v5_hourly_cost, s5["tps_avg"])
        cost_delta = pct_delta(c6, c5)
        cost_rows.append(
            [
                workload,
                threads,
                f"{c6:.4f}",
                f"{c5:.4f}",
                f"{cost_delta:+.2f}%",
            ]
        )

    print("\nPerformance Delta Table (D8s_v6 vs D8s_v5)")
    print_table(
        [
            "workload",
            "threads",
            "v6_tps",
            "v5_tps",
            "tps_delta",
            "v6_p95_ms",
            "v5_p95_ms",
            "p95_improvement",
            "v6_errors",
            "v5_errors",
        ],
        perf_rows,
    )

    print("\nCost/Performance Table (USD per 1k TPS, lower is better)")
    print_table(
        [
            "workload",
            "threads",
            "v6_$per_1k_tps",
            "v5_$per_1k_tps",
            "cost_perf_delta",
        ],
        cost_rows,
    )


if __name__ == "__main__":
    main()
