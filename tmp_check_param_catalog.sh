#!/usr/bin/env bash
set -euo pipefail

echo '=== GV$OB_PARAMETERS schema (key cols) ==='
mysql -h10.100.1.6 -P2881 -uroot@sys -p"OceanBase#!123" -Nse "DESC oceanbase.GV\$OB_PARAMETERS;" | egrep "TENANT_ID|SVR_IP|NAME|VALUE|SCOPE" || true

echo "=== names like hotkey ==="
mysql -h10.100.1.6 -P2881 -uroot@sys -p"OceanBase#!123" -Nse "SELECT DISTINCT name FROM oceanbase.GV\$OB_PARAMETERS WHERE name LIKE '%hotkey%' ORDER BY name;" || true

echo "=== names like writing_throttling ==="
mysql -h10.100.1.6 -P2881 -uroot@sys -p"OceanBase#!123" -Nse "SELECT DISTINCT name FROM oceanbase.GV\$OB_PARAMETERS WHERE name LIKE '%writing_throttling%' ORDER BY name;" || true

echo "=== writing_throttling_trigger_percentage by tenant/server ==="
mysql -h10.100.1.6 -P2881 -uroot@sys -p"OceanBase#!123" -Nse "SELECT p.svr_ip, t.tenant_name, p.value FROM oceanbase.GV\$OB_PARAMETERS p JOIN oceanbase.DBA_OB_TENANTS t ON p.tenant_id=t.tenant_id WHERE p.name='writing_throttling_trigger_percentage' ORDER BY t.tenant_name, p.svr_ip;"