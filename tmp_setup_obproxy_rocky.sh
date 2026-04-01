#!/usr/bin/env bash
set -euo pipefail

NODES=(172.17.1.7 172.17.1.6 172.17.1.5)
RPM_URL="https://mirrors.aliyun.com/oceanbase/community/stable/el/8/x86_64/obproxy-ce-4.3.6.1-2.el8.x86_64.rpm"

for ip in "${NODES[@]}"; do
  echo "=== [${ip}] install obproxy rpm ==="
  ssh -o ConnectTimeout=12 -o StrictHostKeyChecking=accept-new "oceanadmin@${ip}" \
    "sudo dnf -y install ${RPM_URL} >/tmp/obproxy_install.log 2>&1 || sudo dnf -y reinstall ${RPM_URL} >/tmp/obproxy_install.log 2>&1"

  echo "=== [${ip}] configure service ==="
  ssh -o ConnectTimeout=12 -o StrictHostKeyChecking=accept-new "oceanadmin@${ip}" 'bash -s' <<'EOS'
set -euo pipefail
sudo groupadd -f admin
id -u admin >/dev/null 2>&1 || sudo useradd -m -g admin admin
sudo mkdir -p /home/admin/logs /home/admin/etc
sudo chown -R admin:admin /home/admin

OBP_BIN="/home/admin/obproxy-4.3.6.1/bin/obproxy"
if [ ! -x "$OBP_BIN" ]; then
  echo "ERROR: obproxy binary not found at $OBP_BIN" >&2
  exit 2
fi

sudo tee /etc/systemd/system/obproxy.service >/dev/null <<'UNIT'
[Unit]
Description=OceanBase OBProxy
After=network.target

[Service]
Type=simple
User=admin
Group=admin
WorkingDirectory=/home/admin
ExecStart=/home/admin/obproxy-4.3.6.1/bin/obproxy -r "172.17.1.7:2881;172.17.1.6:2881;172.17.1.5:2881" -p 2883 -c ob_cluster -o "enable_strict_kernel_release=false,enable_metadb_used=false,enable_cluster_checkout=false"
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now obproxy
sleep 2
sudo systemctl is-active obproxy
sudo ss -lntp | grep ':2883' || true
EOS

done

echo "=== summary ==="
for ip in "${NODES[@]}"; do
  echo "--- ${ip} ---"
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "oceanadmin@${ip}" 'systemctl is-active obproxy; ss -lntp | grep ":2883" || true; pgrep -af obproxy | head -3 || true'
done
