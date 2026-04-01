#!/bin/bash
set -x
sudo pkill -f "/home/admin/obproxy-4.3.6.1/bin/obproxy" || true
sudo -u admin bash -lc 'nohup /home/admin/obproxy-4.3.6.1/bin/obproxy -p 2883 -r "10.100.1.4:2881;10.100.1.5:2881;10.100.1.6:2881" -c ob_cluster -n obproxy-centos -o "enable_cluster_checkout=false,enable_compression_protocol=false,syslog_level=INFO" > /home/admin/logs/obproxy/startup.log 2>&1 < /dev/null &'
sleep 6
echo "PGREP:"
pgrep -af "/home/admin/obproxy-4.3.6.1/bin/obproxy" || true
echo "PORT:"
sudo ss -lntp | grep :2883 || true
echo "LOG:"
sudo -u admin tail -n 80 /home/admin/logs/obproxy/startup.log || true