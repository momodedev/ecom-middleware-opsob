#!/usr/bin/env bash
set -euo pipefail
NODES=(172.17.1.7 172.17.1.6 172.17.1.5)
RS_LIST="172.17.1.7:2881;172.17.1.6:2881;172.17.1.5:2881"
OBPROXY_O="obproxy_sys_password=6b3f9e06889ad7fc3bd92a289a8f927a99bdc96c,enable_strict_kernel_release=False,rpc_listen_port=2885,enable_cluster_checkout=False,skip_proxy_sys_private_check=True,skip_proxyro_check=True"

run_remote() {
  local ip="$1"
  local cmd="$2"
  ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@"$ip" "$cmd"
}

echo "[PRECHECK]"
for ip in "${NODES[@]}"; do
  echo "===== $ip ====="
  run_remote "$ip" "hostname; ls -l /home/oceanadmin/obproxy/obproxyd.sh || true; pgrep -af obproxy || true; ss -lntp | egrep '(:2883|:2884|:2885)' || true"
done

echo "[WRITE] replace obproxyd.sh"
for ip in "${NODES[@]}"; do
  echo "===== $ip ====="
  run_remote "$ip" "cat > /home/oceanadmin/obproxy/obproxyd.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
OBPROXY_HOME=/home/oceanadmin/obproxy
cd \"\$OBPROXY_HOME\"
exec \"\$OBPROXY_HOME/bin/obproxy\" \\
  --listen_port 2883 \\
  --prometheus_listen_port 2884 \\
  --rs_list \"172.17.1.7:2881;172.17.1.6:2881;172.17.1.5:2881\" \\
  --cluster_name ob_cluster \\
  -o \"obproxy_sys_password=6b3f9e06889ad7fc3bd92a289a8f927a99bdc96c,enable_strict_kernel_release=False,rpc_listen_port=2885,enable_cluster_checkout=False,skip_proxy_sys_private_check=True,skip_proxyro_check=True\"
EOS
chmod +x /home/oceanadmin/obproxy/obproxyd.sh
head -n 20 /home/oceanadmin/obproxy/obproxyd.sh"
done

echo "[RESTART] clean restart obproxy"
for ip in "${NODES[@]}"; do
  echo "===== $ip ====="
  TS=$(date '+%Y-%m-%d %H:%M:%S')
  run_remote "$ip" "echo $TS > /tmp/obproxy_fix_since.txt; pkill -f '/home/oceanadmin/obproxy/bin/obproxy' || true; sleep 2; nohup /home/oceanadmin/obproxy/obproxyd.sh >/home/oceanadmin/obproxy/log/obproxy.stdout.log 2>&1 < /dev/null & disown; sleep 3; pgrep -af '/home/oceanadmin/obproxy/bin/obproxy'"
done

echo "[VERIFY LISTEN]"
for ip in "${NODES[@]}"; do
  echo "===== $ip ====="
  run_remote "$ip" "ss -lntp | egrep '(:2883\s|:2884\s|:2885\s|:2883$|:2884$|:2885$)' || true"
done

echo "[VERIFY MYSQL THROUGH 172.17.1.7:2883]"
ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 "mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant#ob_cluster -p'OceanBase#!123' -e 'select 1 as ok;'"
ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=no oceanadmin@172.17.1.7 "mysql -h127.0.0.1 -P2883 -uroot@sbtest_tenant -p'OceanBase#!123' -e 'select 1 as ok;'"

echo "[CHECK NEW CR_INIT_FAILED]"
for ip in "${NODES[@]}"; do
  echo "===== $ip ====="
  run_remote "$ip" "SINCE=\$(cat /tmp/obproxy_fix_since.txt 2>/dev/null || date '+%Y-%m-%d %H:%M:%S'); echo since=\$SINCE; if [ -f /home/oceanadmin/obproxy/log/obproxy.log ]; then awk -v s=\"\$SINCE\" '\''$0 >= s'\'' /home/oceanadmin/obproxy/log/obproxy.log | grep 'CR_INIT_FAILED' || true; fi; if [ -f /home/oceanadmin/obproxy/log/obproxy.stdout.log ]; then grep 'CR_INIT_FAILED' /home/oceanadmin/obproxy/log/obproxy.stdout.log | tail -n 20 || true; fi"
done
