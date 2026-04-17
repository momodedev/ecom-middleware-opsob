#!/usr/bin/env python3
"""
OceanBase Benchmark Result Analyzer & Comparator
Compares baseline vs tuned performance results
"""

import csv
import sys
from pathlib import Path
from typing import Dict, List, Tuple

def load_csv(filepath: str) -> List[Dict]:
    """Load benchmark CSV file"""
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        return list(reader)

def parse_results(data: List[Dict]) -> Dict:
    """Parse results into organized structure"""
    results = {
        'oltp_read_only': {},
        'oltp_read_write': {}
    }
    
    for row in data:
        workload = row['workload']
        threads = int(row['threads'])
        
        results[workload][threads] = {
            'tps': float(row['tps']),
            'p95_ms': float(row['p95_ms']),
            'avg_latency_ms': float(row['avg_latency_ms']),
            'total_queries': int(row['total_queries']),
            'errors': int(row['errors']),
            'status': row['status']
        }
    
    return results

def compare_results(baseline: Dict, tuned: Dict) -> Dict:
    """Compare baseline vs tuned results"""
    comparison = {
        'oltp_read_only': {},
        'oltp_read_write': {}
    }
    
    for workload in baseline:
        for threads in baseline[workload]:
            if threads not in tuned[workload]:
                continue
            
            base = baseline[workload][threads]
            tune = tuned[workload][threads]
            
            tps_improvement = ((tune['tps'] - base['tps']) / base['tps']) * 100
            latency_improvement = ((base['p95_ms'] - tune['p95_ms']) / base['p95_ms']) * 100
            avg_latency_improvement = ((base['avg_latency_ms'] - tune['avg_latency_ms']) / base['avg_latency_ms']) * 100
            
            comparison[workload][threads] = {
                'tps': {
                    'baseline': base['tps'],
                    'tuned': tune['tps'],
                    'delta': tune['tps'] - base['tps'],
                    'percent': tps_improvement
                },
                'p95_ms': {
                    'baseline': base['p95_ms'],
                    'tuned': tune['p95_ms'],
                    'delta': tune['p95_ms'] - base['p95_ms'],
                    'percent': latency_improvement
                },
                'avg_latency_ms': {
                    'baseline': base['avg_latency_ms'],
                    'tuned': tune['avg_latency_ms'],
                    'delta': tune['avg_latency_ms'] - base['avg_latency_ms'],
                    'percent': avg_latency_improvement
                }
            }
    
    return comparison

def generate_markdown_report(baseline_file: str, tuned_file: str, output_file: str = 'TUNING_RESULTS.md'):
    """Generate markdown report"""
    print(f"Loading baseline: {baseline_file}")
    baseline = parse_results(load_csv(baseline_file))
    
    print(f"Loading tuned: {tuned_file}")
    tuned = parse_results(load_csv(tuned_file))
    
    print("Comparing results...")
    comparison = compare_results(baseline, tuned)
    
    # Generate report
    report = f"""# OceanBase Performance Tuning Results

**Comparison Date**: 2026-04-17
**Baseline**: 2026-04-16 (Default parameters)
**Tuned**: 2026-04-17 (6 tuning parameters applied)

## Summary

### Applied Parameters
- ✅ `enable_adaptive_plan_cache` = True
- ✅ `freeze_trigger_percentage` = 15% (from 20%)
- ✅ `ob_enable_batched_multi_statement` = True
- ✅ `compaction_high_thread_score` = 4
- ✅ `net_thread_count` = 8
- ✅ `cpu_quota_concurrency` = 12

---

## oltp_read_only (Read-Only Workload)

"""
    
    # RO Results
    report += "| Threads | Baseline TPS | Tuned TPS | TPS Δ | TPS Δ% | P95 Base | P95 Tuned | P95 Δ% |\n"
    report += "|---------|--------------|----------|-------|--------|----------|-----------|--------|\n"
    
    for threads in sorted(comparison['oltp_read_only'].keys()):
        comp = comparison['oltp_read_only'][threads]
        tps = comp['tps']
        p95 = comp['p95_ms']
        
        tps_arrow = "↑" if tps['percent'] > 0 else "↓" if tps['percent'] < 0 else "="
        p95_arrow = "↓" if p95['percent'] > 0 else "↑" if p95['percent'] < 0 else "="
        
        report += f"| {threads:3d} | {tps['baseline']:12.2f} | {tps['tuned']:8.2f} | {tps['delta']:6.2f} | {tps_arrow}{tps['percent']:6.2f}% | {p95['baseline']:8.2f} | {p95['tuned']:9.2f} | {p95_arrow}{p95['percent']:7.2f}% |\n"
    
    # RW Results
    report += "\n## oltp_read_write (Read-Write Workload)\n\n"
    report += "| Threads | Baseline TPS | Tuned TPS | TPS Δ | TPS Δ% | P95 Base | P95 Tuned | P95 Δ% |\n"
    report += "|---------|--------------|----------|-------|--------|----------|-----------|--------|\n"
    
    for threads in sorted(comparison['oltp_read_write'].keys()):
        comp = comparison['oltp_read_write'][threads]
        tps = comp['tps']
        p95 = comp['p95_ms']
        
        tps_arrow = "↑" if tps['percent'] > 0 else "↓" if tps['percent'] < 0 else "="
        p95_arrow = "↓" if p95['percent'] > 0 else "↑" if p95['percent'] < 0 else "="
        
        report += f"| {threads:3d} | {tps['baseline']:12.2f} | {tps['tuned']:8.2f} | {tps['delta']:6.2f} | {tps_arrow}{tps['percent']:6.2f}% | {p95['baseline']:8.2f} | {p95['tuned']:9.2f} | {p95_arrow}{p95['percent']:7.2f}% |\n"
    
    # Summary statistics
    ro_tps = [comparison['oltp_read_only'][t]['tps']['percent'] for t in comparison['oltp_read_only']]
    rw_tps = [comparison['oltp_read_write'][t]['tps']['percent'] for t in comparison['oltp_read_write']]
    ro_p95 = [comparison['oltp_read_only'][t]['p95_ms']['percent'] for t in comparison['oltp_read_only']]
    rw_p95 = [comparison['oltp_read_write'][t]['p95_ms']['percent'] for t in comparison['oltp_read_write']]
    
    report += f"""
## Overall Impact Summary

| Metric | Read-Only | Read-Write |
|--------|-----------|------------|
| **Avg TPS Change** | {sum(ro_tps)/len(ro_tps):+.2f}% | {sum(rw_tps)/len(rw_tps):+.2f}% |
| **Avg P95 Latency Improvement** | {sum(ro_p95)/len(ro_p95):+.2f}% | {sum(rw_p95)/len(rw_p95):+.2f}% |
| **Best Case (TPS)** | {max(ro_tps):+.2f}% @ {list(comparison['oltp_read_only'].keys())[ro_tps.index(max(ro_tps))]}t | {max(rw_tps):+.2f}% @ {list(comparison['oltp_read_write'].keys())[rw_tps.index(max(rw_tps))]}t |
| **Worst Case (TPS)** | {min(ro_tps):+.2f}% @ {list(comparison['oltp_read_only'].keys())[ro_tps.index(min(ro_tps))]}t | {min(rw_tps):+.2f}% @ {list(comparison['oltp_read_write'].keys())[rw_tps.index(min(rw_tps))]}t |

## Conclusion

"""
    
    # Calculate final verdict
    all_tps = ro_tps + rw_tps
    avg_improvement = sum(all_tps) / len(all_tps)
    
    if avg_improvement > 10:
        report += f"""✅ **SIGNIFICANT IMPROVEMENT** - Average {avg_improvement:+.2f}% throughput gain

This tuning configuration is **highly recommended** for production deployment.
"""
    elif avg_improvement > 0:
        report += f"""✅ **POSITIVE IMPACT** - Average {avg_improvement:+.2f}% throughput gain

This tuning configuration provides measurable performance improvements and is **recommended** for production.
"""
    elif avg_improvement > -5:
        report += f"""⚠️ **NEUTRAL** - Average {avg_improvement:+.2f}% change

This tuning has minimal impact. Consider reverting or investigating specific parameters.
"""
    else:
        report += f"""❌ **NEGATIVE IMPACT** - Average {avg_improvement:+.2f}% throughput loss

This tuning configuration is **not recommended** for current workload profile.
Consider reverting and profiling individual parameters.
"""
    
    # Write report
    print(f"Writing report to {output_file}")
    with open(output_file, 'w') as f:
        f.write(report)
    
    print(f"✅ Report generated: {output_file}")
    return report

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <baseline_csv> <tuned_csv> [output_file]")
        sys.exit(1)
    
    output = sys.argv[3] if len(sys.argv) > 3 else 'TUNING_RESULTS.md'
    generate_markdown_report(sys.argv[1], sys.argv[2], output)
