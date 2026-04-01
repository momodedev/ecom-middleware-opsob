#!/usr/bin/env bash
set -euo pipefail
for ip in 172.17.1.6 172.17.1.5; do
  echo "===== fix $ip ====="
  ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@$ip <<'EOS'
set +e
ps -ef | grep '/home/oceanadmin/obproxy/obproxyd.sh /home/oceanadmin/obproxy' | grep -v grep | awk '{print $2}' | xargs -r kill -9
pkill -x obproxy
sleep 2
nohup /home/oceanadmin/obproxy/obproxyd.sh >/tmp/obproxy.stdout.log 2>&1 < /dev/null &
sleep 5
pgrep -af obproxy || true
ss -lntp | grep :2883 || true
ss -lntp | grep :2884 || true
ss -lntp | grep :2885 || true
EOS
done

echo "===== verify args all ====="
for ip in 172.17.1.7 172.17.1.6 172.17.1.5; do
  echo "--- $ip ---"
  ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@$ip "pgrep -af '/home/oceanadmin/obproxy/bin/obproxy'"
done

echo "===== mysql via 172.17.1.7:2883 ====="
ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 "mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant#ob_cluster -p'OceanBase#!123' -e 'select 1 as ok;'"
ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 "mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -p'OceanBase#!123' -e 'select 1 as ok;'"

echo "===== new CR_INIT_FAILED check ====="
for ip in 172.17.1.7 172.17.1.6 172.17.1.5; do
  echo "--- $ip ---"
  ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@$ip "echo since=\$(cat /tmp/obproxy_fix_since.txt 2>/dev/null || echo unknown); find /home/oceanadmin/obproxy/log -maxdepth 1 -type f -name '*.log' -print | while read f; do echo FILE:\$f; tail -n 200 \$f | grep 'CR_INIT_FAILED' || true; done"
done
