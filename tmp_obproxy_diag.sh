#!/bin/bash
set -e
ls -l /etc/systemd/system/obproxy.service /tmp/obproxy.service 2>/dev/null || true
echo "--- logs ---"
sudo -u admin bash -lc 'ls -l /home/admin/obproxy-4.3.6.1/log 2>/dev/null || true'
sudo -u admin bash -lc 'tail -n 120 /home/admin/obproxy-4.3.6.1/log/obproxy.log 2>/dev/null || true'
sudo -u admin bash -lc 'tail -n 120 /home/admin/logs/obproxy/startup.log 2>/dev/null || true'
echo "--- login tests ---"
for u in 'root@sys#ob_cluster' 'root@sys' 'root@sys#obcluster' 'proxyro@sys#ob_cluster' 'root@proxysys'; do
  echo "USER:$u"
  mysql -h 127.0.0.1 -P 2883 -u"$u" -pOceanBase#!123 -N -e 'select 1;' 2>&1 | head -5 || true
  echo "---"
done