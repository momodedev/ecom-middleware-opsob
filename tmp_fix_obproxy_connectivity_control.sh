#!/usr/bin/env bash
set -euo pipefail

echo "=== 1) Inspect OBProxy runtime and config on 172.17.1.7 ==="
ssh -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 '
  set -e
  pgrep -af obproxy || true
  ls -la ~/obproxy ~/obproxy/etc ~/obproxy/conf 2>/dev/null || true
  grep -RInE "proxyro|sys_password|observer_sys_password|cluster_name|appname" ~/obproxy 2>/dev/null | head -120 || true
'

echo "=== 2) Ensure proxyro user/password exists in sys tenant ==="
mysql -h 172.17.1.7 -P 2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "
CREATE USER IF NOT EXISTS proxyro IDENTIFIED BY 'OceanBase#!123';
ALTER USER proxyro IDENTIFIED BY 'OceanBase#!123';
GRANT SELECT ON oceanbase.* TO proxyro;
"

echo "=== 3) Restart obproxy daemon on all Rocky nodes ==="
for node in 172.17.1.7 172.17.1.6 172.17.1.5; do
  echo "--- ${node} ---"
  ssh -o StrictHostKeyChecking=no oceanadmin@${node} '
    pkill -f obproxy || true
    sleep 1
    nohup ~/obproxy/obproxyd.sh ~/obproxy '"${node}"' 2883 daemon >/tmp/obproxy_restart.log 2>&1 &
    sleep 3
    pgrep -af obproxy || true
    ss -lntp | grep 2883 || true
  '
done

echo "=== 4) Validate OBProxy login path ==="
set +e
mysql -h 172.17.1.7 -P 2883 -u root@sbtest_tenant#ob_cluster -p'OceanBase#!123' -e 'SELECT NOW() AS ts;' 
rc1=$?
mysql -h 172.17.1.7 -P 2883 -u root@sbtest_tenant -p'OceanBase#!123' -e 'SELECT NOW() AS ts;' 
rc2=$?
set -e

echo "login test with #ob_cluster rc=${rc1}"
echo "login test without #ob_cluster rc=${rc2}"

echo "=== 5) Tail auth errors in obproxy log ==="
ssh -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 '
  tail -n 120 ~/obproxy/log/obproxy.log | egrep -i "proxyro|1045|Access denied|CR_INIT_FAILED|cluster resource create complete" || true
'

echo "DONE"
