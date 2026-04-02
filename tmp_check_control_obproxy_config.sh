#!/usr/bin/env bash
set -euo pipefail

echo "=== try SHOW PROXYCONFIG via root@sys#ob_cluster ==="
mysql -h127.0.0.1 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "SHOW PROXYCONFIG LIKE 'hotkey_mitigation'; SHOW PROXYCONFIG LIKE 'writing_throttling_trigger_percentage';" || echo "root@sys show proxyconfig failed"

echo "=== try proxysys account without password ==="
mysql -h127.0.0.1 -P2883 -uroot@proxysys -Nse "SHOW PROXYCONFIG LIKE 'hotkey_mitigation'; SHOW PROXYCONFIG LIKE 'writing_throttling_trigger_percentage';" || echo "root@proxysys show proxyconfig failed"

echo "=== try list proxyconfig names around hot/writing ==="
mysql -h127.0.0.1 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "SHOW PROXYCONFIG" 2>/dev/null | egrep -i "hot|writing|thrott" || echo "no matching proxyconfig names found"