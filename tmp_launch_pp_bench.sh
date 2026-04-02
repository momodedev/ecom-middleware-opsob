#!/usr/bin/env bash
set -euo pipefail
cd /tmp/ecom-middleware-opsob-t6
mkdir -p /tmp/ecom-middleware-opsob-t6_untracked_backup
for f in ansible_ob/scripts/run_oceanbase_benchmark_nmysql_p.sh ansible_ob_centos/scripts/run_oceanbase_benchmark_nmysql_p.sh; do
  if [ -f "$f" ]; then
    mv "$f" "/tmp/ecom-middleware-opsob-t6_untracked_backup/$(basename "$f").$(date -u +%Y%m%dT%H%M%SZ)"
  fi
done
git pull origin t6
cd /tmp/ecom-middleware-opsob-t6/ansible_ob_centos/scripts
chmod +x run_oceanbase_benchmark_nmysql_pp.sh
TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG=/tmp/run_oceanbase_benchmark_nmysql_pp_${TS}.log
nohup ./run_oceanbase_benchmark_nmysql_pp.sh d8s_v5_centos_nmysql_pp 127.0.0.1 'root@sbtest_tenant#ob_cluster' 'OceanBase#!123' sbtest '10.100.1.4 10.100.1.5 10.100.1.6' 2883 > "${LOG}" 2>&1 < /dev/null &
echo "PID:$!"
echo "LOG:${LOG}"