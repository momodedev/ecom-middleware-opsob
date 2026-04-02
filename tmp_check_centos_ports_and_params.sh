#!/usr/bin/env bash
set -euo pipefail

echo "=== TCP reachability from control-node ==="
for ip in 10.100.1.4 10.100.1.5 10.100.1.6; do
  for p in 2881 2882 2883 2884 2886; do
    if timeout 2 bash -c "</dev/tcp/${ip}/${p}" >/dev/null 2>&1; then
      echo "${ip}:${p} OPEN"
    else
      echo "${ip}:${p} CLOSED"
    fi
  done
 done

echo "=== DB parameter check on observer endpoint (2881) ==="
mysql -h10.100.1.6 -P2881 -uroot@sys -p"OceanBase#!123" -Nse "SELECT svr_ip, name, value FROM oceanbase.GV\$OB_PARAMETERS WHERE name IN ('hotkey_mitigation','writing_throttling_trigger_percentage') ORDER BY name,svr_ip;" || echo "observer-param-query-failed"