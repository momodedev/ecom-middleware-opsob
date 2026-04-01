#!/usr/bin/env bash
set -euo pipefail

# 1) Ensure internal OBProxy account password is simple and known
mysql -h10.100.1.4 -P2881 -uroot@sys -p'OceanBase#!123' -e "ALTER USER proxyro IDENTIFIED BY 'Proxyro12345';"

# 2) Stop any old process to avoid port conflicts
pkill -9 obproxy >/dev/null 2>&1 || true

# 3) Install binaries into SELinux-safe location for systemd execution
rm -rf /opt/obproxy-4.3.6.1
mkdir -p /opt/obproxy-4.3.6.1
cp -a /home/admin/obproxy-4.3.6.1/. /opt/obproxy-4.3.6.1/
chown -R admin:admin /opt/obproxy-4.3.6.1
restorecon -RFv /opt/obproxy-4.3.6.1 >/tmp/restorecon_obproxy.log 2>&1 || true

# 4) Run obproxy directly from systemd
cat >/etc/systemd/system/obproxy.service <<'EOF'
[Unit]
Description=OceanBase OBProxy
After=network.target

[Service]
Type=simple
User=admin
Group=admin
WorkingDirectory=/opt/obproxy-4.3.6.1
Environment=OBPROXY_ROOT=/opt/obproxy-4.3.6.1
ExecStart=/opt/obproxy-4.3.6.1/bin/obproxy -N -p 2883 -r 10.100.1.4:2881 -c ob_cluster -n obproxy-centos -o enable_cluster_checkout=false,enable_compression_protocol=false,observer_sys_username=proxyro,observer_sys_password=Proxyro12345,syslog_level=INFO
Restart=always
RestartSec=5
LimitNOFILE=655350

[Install]
WantedBy=multi-user.target
EOF

restorecon -v /etc/systemd/system/obproxy.service || true
chown root:root /etc/systemd/system/obproxy.service
chmod 644 /etc/systemd/system/obproxy.service
systemctl disable --now obproxy.service >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable --now obproxy.service
sleep 3

systemctl status obproxy.service --no-pager -l | sed -n '1,40p'
echo '---'
mysql -h127.0.0.1 -P2883 -uroot@sys#ob_cluster -p'OceanBase#!123' -e "select 1 as via_proxy;" || true
echo '---'
tail -n 60 /home/admin/obproxy-4.3.6.1/log/obproxy.log | sed -n '1,120p'
