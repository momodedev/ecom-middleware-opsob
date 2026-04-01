#!/usr/bin/env bash
set -euo pipefail
NODES=(172.17.1.7 172.17.1.6 172.17.1.5)

echo "[RESTART CLEAN]"
for ip in "${NODES[@]}"; do
  echo "===== $ip ====="
  ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@"$ip" "set +e; date '+%Y-%m-%d %H:%M:%S' > /tmp/obproxy_fix_since.txt; pkill -x obproxy; pkill -f 'bash /home/oceanadmin/obproxy/obproxyd.sh'; sleep 2; nohup /home/oceanadmin/obproxy/obproxyd.sh >/home/oceanadmin/obproxy/log/obproxy.stdout.log 2>&1 < /dev/null & sleep 5; pgrep -af obproxy || true"
done

echo "[VERIFY LISTEN 2883]"
for ip in "${NODES[@]}"; do
  echo "===== $ip ====="
  ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@"$ip" "ss -lntp | grep ':2883'"
done

echo "[VERIFY MYSQL CONNECTIVITY through 172.17.1.7:2883]"
ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 "mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant#ob_cluster -p'OceanBase#!123' -e 'select 1 as ok;'"
ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 "mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -p'OceanBase#!123' -e 'select 1 as ok;'"

echo "[CHECK NEW CR_INIT_FAILED]"
for ip in "${NODES[@]}"; do
  echo "===== $ip ====="
  ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@"$ip" "echo since=\$(cat /tmp/obproxy_fix_since.txt); if [ -f /home/oceanadmin/obproxy/log/obproxy.stdout.log ]; then tail -n 200 /home/oceanadmin/obproxy/log/obproxy.stdout.log | grep 'CR_INIT_FAILED' || true; fi; if [ -f /home/oceanadmin/obproxy/log/obproxy.log ]; then tail -n 200 /home/oceanadmin/obproxy/log/obproxy.log | grep 'CR_INIT_FAILED' || true; fi"
done
