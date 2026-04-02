#!/usr/bin/env bash
set -euo pipefail
IPS=(10.100.1.4 10.100.1.5 10.100.1.6)
for ip in "${IPS[@]}"; do
  echo "================ ${ip} ================"
  ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no oceanadmin@${ip} '
    echo "host=$(hostname)"
    echo "-- obproxy process --"
    ps -ef | grep -E "[o]bproxy" || true
    echo "-- obproxy config files --"
    find /home/oceanbase /etc -maxdepth 5 -type f \( -name "*obproxy*" -o -name "proxy*config*" \) 2>/dev/null | head -n 30
    echo "-- grep special keys in possible config roots --"
    grep -RIn "hotkey_mitigation|writing_throttling_trigger_percentage" /home/oceanbase/oceanbase /etc 2>/dev/null | head -n 40 || true
  '
  echo "-- runtime check via OBProxy endpoint ${ip}:2883 (DB params) --"
  mysql -h${ip} -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "SELECT svr_ip, name, value FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN ('hotkey_mitigation','writing_throttling_trigger_percentage') ORDER BY name, svr_ip;" || echo "db-param-query-failed"
  echo "-- try SHOW PROXYCONFIG on ${ip}:2883 --"
  mysql -h${ip} -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "SHOW PROXYCONFIG LIKE 'hotkey_mitigation'; SHOW PROXYCONFIG LIKE 'writing_throttling_trigger_percentage';" || echo "show-proxyconfig-failed"
  echo
 done