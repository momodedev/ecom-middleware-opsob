#!/bin/bash
set -e
sudo pkill -9 -f '/home/admin/obproxy-4.3.6.1/bin/obproxy' || true
sudo tee /etc/systemd/system/obproxy.service >/dev/null <<'UNIT'
[Unit]
Description=OceanBase OBProxy
After=network.target

[Service]
Type=simple
User=admin
Group=admin
WorkingDirectory=/home/admin/obproxy-4.3.6.1
ExecStart=/bin/bash -lc '/home/admin/obproxy-4.3.6.1/bin/obproxy -p 2883 -r "10.100.1.4:2881;10.100.1.5:2881;10.100.1.6:2881" -c ob_cluster -n obproxy-centos -o "enable_cluster_checkout=false,enable_compression_protocol=false,observer_sys_username=proxyro,observer_sys_password=OceanBase#!123,syslog_level=INFO"'
Restart=always
RestartSec=5
LimitNOFILE=655350

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable obproxy
sudo systemctl restart obproxy
sleep 5
sudo systemctl --no-pager -l status obproxy | head -40
echo '---'
ps -ef | grep '[o]bproxy -p 2883'
echo '---'
mysql -h 127.0.0.1 -P 2883 -uroot@sys#ob_cluster -pOceanBase#!123 -N -e 'select 1;'