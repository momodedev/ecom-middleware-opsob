#!/usr/bin/env bash
set -euo pipefail

CONTROL_HOST="20.245.23.176"
CONTROL_USER="azureadmin"
SSH_KEY="$HOME/.ssh/id_rsa"
SSH_PORT="6666"

run_remote() {
  local cmd="$1"
  ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -i "$SSH_KEY" "$CONTROL_USER@$CONTROL_HOST" "$cmd"
}

echo "=== 1) Inspect OBProxy runtime and config on 172.17.1.7 ==="
run_remote "ssh -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 'set -e; pgrep -af obproxy || true; ls -la ~/obproxy ~/obproxy/etc ~/obproxy/conf 2>/dev/null || true; grep -RInE ""proxyro|sys_password|observer_sys_password|cluster_name|appname"" ~/obproxy 2>/dev/null | head -120 || true'"

echo "=== 2) Ensure proxyro user/password exists in sys tenant ==="
run_remote "mysql -h 172.17.1.7 -P 2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e \"CREATE USER IF NOT EXISTS proxyro IDENTIFIED BY 'OceanBase#!123'; ALTER USER proxyro IDENTIFIED BY 'OceanBase#!123'; GRANT SELECT ON oceanbase.* TO proxyro;\""

echo "=== 3) Restart obproxy daemon on all Rocky nodes ==="
for node in 172.17.1.7 172.17.1.6 172.17.1.5; do
  run_remote "ssh -o StrictHostKeyChecking=no oceanadmin@${node} 'set -e; pkill -f obproxy || true; sleep 1; nohup ~/obproxy/obproxyd.sh ~/obproxy ${node} 2883 daemon >/tmp/obproxy_restart.log 2>&1 & sleep 2; pgrep -af obproxy; ss -lntp | grep 2883 || true'"
done

echo "=== 4) Validate OBProxy login path ==="
run_remote "mysql -h 172.17.1.7 -P 2883 -u root@sbtest_tenant#ob_cluster -p'OceanBase#!123' -e 'SELECT now();'"
run_remote "mysql -h 172.17.1.7 -P 2883 -u root@sbtest_tenant -p'OceanBase#!123' -e 'SELECT now();' || true"

echo "=== 5) Check latest obproxy log for remaining auth errors ==="
run_remote "ssh -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 'tail -n 60 ~/obproxy/log/obproxy.log | egrep -i ""proxyro|1045|Access denied|CR_INIT_FAILED|cluster resource create complete"" || true'"

echo "DONE"
