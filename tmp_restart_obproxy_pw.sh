#!/bin/bash
set -e
sudo pkill -f '/home/admin/obproxy-4.3.6.1/bin/obproxy' || true
sudo -u admin bash -lc 'cd /home/admin/obproxy-4.3.6.1 && nohup ./bin/obproxy -p 2883 -r "10.100.1.4:2881;10.100.1.5:2881;10.100.1.6:2881" -c ob_cluster -n obproxy-centos -o "enable_cluster_checkout=false,enable_compression_protocol=false,observer_sys_username=proxyro,observer_sys_password=OceanBase#!123,syslog_level=INFO" > /home/admin/logs/obproxy/startup.log 2>&1 < /dev/null &'
sleep 6
sudo ss -lntp | grep :2883
mysql -h 127.0.0.1 -P 2883 -uroot@sys#ob_cluster -pOceanBase#!123 -N -e 'select 1;'