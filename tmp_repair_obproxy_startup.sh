#!/usr/bin/env bash
set -euo pipefail

NODES=(172.17.1.7 172.17.1.6 172.17.1.5)
RS_LIST="172.17.1.7:2881;172.17.1.6:2881;172.17.1.5:2881"
CLUSTER_NAME="ob_cluster"
OBPROXY_SYS_PWD_HASH="6b3f9e06889ad7fc3bd92a289a8f927a99bdc96c"

for n in "${NODES[@]}"; do
  echo "=== Repairing OBProxy launcher on ${n} ==="
  ssh -o StrictHostKeyChecking=no oceanadmin@"${n}" "cp -f /home/oceanadmin/obproxy/obproxyd.sh /home/oceanadmin/obproxy/obproxyd.sh.bak.
$(date +%s)"

  ssh -o StrictHostKeyChecking=no oceanadmin@"${n}" "cat > /home/oceanadmin/obproxy/obproxyd.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

path="$1"
ip="$2"
port="$3"

obproxy_path="$path/bin/obproxy"
log_path="$path/log/obproxy.log"
run_dir="$path/run"
mkdir -p "$run_dir"

start_obproxy() {
  pkill -f "$obproxy_path --listen_port ${port}" || true
  sleep 1
  nohup "$obproxy_path" \
    -o "obproxy_sys_password=${OBPROXY_SYS_PWD_HASH},enable_strict_kernel_release=False,rpc_listen_port=2885,enable_cluster_checkout=False,skip_proxy_sys_private_check=True,skip_proxyro_check=True" \
    --listen_port "$port" \
    --prometheus_listen_port 2884 \
    --rs_list "${RS_LIST}" \
    --cluster_name "${CLUSTER_NAME}" \
    >> "$log_path" 2>&1 &
  echo $! > "$run_dir/obproxy-${ip}-${port}.pid"
}

if [[ "${4:-}" == "daemon" ]]; then
  start_obproxy
  while true; do
    sleep 3
    if ! pgrep -f "$obproxy_path --listen_port ${port}" >/dev/null; then
      start_obproxy
    fi
  done
else
  nohup bash "$0" "$path" "$ip" "$port" daemon >/tmp/obproxyd-supervisor.log 2>&1 &
fi
EOF
chmod +x /home/oceanadmin/obproxy/obproxyd.sh"

  ssh -o StrictHostKeyChecking=no oceanadmin@"${n}" "pkill -f /home/oceanadmin/obproxy/bin/obproxy || true; pkill -f obproxyd.sh || true; nohup /home/oceanadmin/obproxy/obproxyd.sh /home/oceanadmin/obproxy ${n} 2883 daemon >/tmp/obproxy_repair.log 2>&1 & sleep 3; pgrep -af obproxy; ss -lntp | grep 2883 || true"
done

echo "=== Validate login through OBProxy ==="
mysql -h 172.17.1.7 -P 2883 -u root@sbtest_tenant#ob_cluster -p'OceanBase#!123' -e "SELECT NOW() AS ts;"
