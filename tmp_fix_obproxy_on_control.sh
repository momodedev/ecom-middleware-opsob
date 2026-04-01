#!/usr/bin/env bash
set -euo pipefail

NODES=(172.17.1.7 172.17.1.6 172.17.1.5)
RS_LIST="172.17.1.7:2881;172.17.1.6:2881;172.17.1.5:2881"
OBPROXY_HASH="6b3f9e06889ad7fc3bd92a289a8f927a99bdc96c"

for node in "${NODES[@]}"; do
  echo "=== ${node}: backup + rewrite launcher ==="
  ssh -o StrictHostKeyChecking=no oceanadmin@${node} "cp -f /home/oceanadmin/obproxy/obproxyd.sh /home/oceanadmin/obproxy/obproxyd.sh.bak.$(date +%s)"

  ssh -o StrictHostKeyChecking=no oceanadmin@${node} "cat > /home/oceanadmin/obproxy/obproxyd.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

path="\$1"
ip="\$2"
port="\$3"

OBPROXY_BIN="\$path/bin/obproxy"
RUN_DIR="\$path/run"
LOG_FILE="\$path/log/obproxy.log"
mkdir -p "\$RUN_DIR"

start_once() {
  pkill -f "\$OBPROXY_BIN --listen_port \$port" || true
  sleep 1
  nohup "\$OBPROXY_BIN" \
    -o "obproxy_sys_password=6b3f9e06889ad7fc3bd92a289a8f927a99bdc96c,enable_strict_kernel_release=False,rpc_listen_port=2885,enable_cluster_checkout=False,skip_proxy_sys_private_check=True,skip_proxyro_check=True" \
    --listen_port "\$port" \
    --prometheus_listen_port 2884 \
    --rs_list "172.17.1.7:2881;172.17.1.6:2881;172.17.1.5:2881" \
    --cluster_name "ob_cluster" \
    >> "\$LOG_FILE" 2>&1 &
  echo \$! > "\$RUN_DIR/obproxy-\${ip}-\${port}.pid"
}

if [[ "\${4:-}" == "daemon" ]]; then
  start_once
  while true; do
    sleep 3
    if ! pgrep -f "\$OBPROXY_BIN --listen_port \$port" >/dev/null; then
      start_once
    fi
  done
else
  nohup bash "\$0" "\$path" "\$ip" "\$port" daemon >/tmp/obproxyd-supervisor.log 2>&1 &
fi
EOF
chmod +x /home/oceanadmin/obproxy/obproxyd.sh"

  echo "=== ${node}: restart obproxy ==="
  ssh -o StrictHostKeyChecking=no oceanadmin@${node} "pkill -f '/home/oceanadmin/obproxy/bin/obproxy' || true; pkill -f 'obproxyd.sh' || true; nohup /home/oceanadmin/obproxy/obproxyd.sh /home/oceanadmin/obproxy ${node} 2883 daemon >/tmp/obproxy_repair.log 2>&1 & sleep 3; pgrep -af obproxy; ss -lntp | grep 2883"
done

echo "=== Validate via control node ==="
set +e
mysql -h 172.17.1.7 -P 2883 -u root@sbtest_tenant#ob_cluster -p'OceanBase#!123' -e 'SELECT 1 AS ok;' 
RC1=$?
mysql -h 172.17.1.7 -P 2883 -u root@sbtest_tenant -p'OceanBase#!123' -e 'SELECT 1 AS ok;' 
RC2=$?
set -e

echo "rc(root@sbtest_tenant#ob_cluster)=$RC1"
echo "rc(root@sbtest_tenant)=$RC2"

echo "=== Fresh error scan ==="
ssh -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 "tail -n 120 /home/oceanadmin/obproxy/log/obproxy.log | egrep -i 'CR_INIT_FAILED|Access denied for user .proxyro.|1045' || true"

echo "DONE"
