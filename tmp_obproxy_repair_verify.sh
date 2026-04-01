#!/usr/bin/env bash
set -euo pipefail
NODES=(172.17.1.7 172.17.1.6 172.17.1.5)

echo "[RESTART-RETRY]"
for ip in "${NODES[@]}"; do
  echo "===== $ip ====="
  ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@"$ip" "date '+%Y-%m-%d %H:%M:%S' > /tmp/obproxy_fix_since.txt; pkill -f '/home/oceanadmin/obproxy/bin/obproxy' || true; pkill -f '/home/oceanadmin/obproxy/obproxyd.sh' || true; sleep 2; nohup /home/oceanadmin/obproxy/obproxyd.sh >/home/oceanadmin/obproxy/log/obproxy.stdout.log 2>&1 < /dev/null & disown; sleep 4; pgrep -af '/home/oceanadmin/obproxy/bin/obproxy' || true"
done

echo "[VERIFY LISTEN 2883]"
for ip in "${NODES[@]}"; do
  echo "===== $ip ====="
  ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@"$ip" "ss -lntp | grep ':2883' || true"
done

echo "[VERIFY LISTEN 2884/2885]"
for ip in "${NODES[@]}"; do
  echo "===== $ip ====="
  ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@"$ip" "ss -lntp | egrep '(:2884|:2885)' || true"
done

echo "[MYSQL CONNECTIVITY via 172.17.1.7:2883]"
ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 "mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant#ob_cluster -p'OceanBase#!123' -e 'select 1 as ok;'"
ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 "mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -p'OceanBase#!123' -e 'select 1 as ok;'"

echo "[CHECK NEW CR_INIT_FAILED AFTER FIX]"
for ip in "${NODES[@]}"; do
  echo "===== $ip ====="
  ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@"$ip" "SINCE=\$(cat /tmp/obproxy_fix_since.txt 2>/dev/null || date '+%Y-%m-%d %H:%M:%S'); echo since=\$SINCE; if [ -f /home/oceanadmin/obproxy/log/obproxy.log ]; then sed -n '/CR_INIT_FAILED/p' /home/oceanadmin/obproxy/log/obproxy.log | tail -n 20; fi; if [ -f /home/oceanadmin/obproxy/log/obproxy.stdout.log ]; then sed -n '/CR_INIT_FAILED/p' /home/oceanadmin/obproxy/log/obproxy.stdout.log | tail -n 20; fi"
done
