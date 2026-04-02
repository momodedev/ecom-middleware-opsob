#!/usr/bin/env bash
set -euo pipefail

DB_HOST=172.17.1.7
DB_PORT=2883
DB_USER='root@sys#ob_cluster'
DB_PASS='OceanBase#!123'
SERVERS=(172.17.1.5:2882 172.17.1.6:2882 172.17.1.7:2882)

sql() {
  mysql -h"${DB_HOST}" -P"${DB_PORT}" -u"${DB_USER}" -p"${DB_PASS}" -Nse "$1"
}

wait_active() {
  local ipport="$1"
  local ip="${ipport%%:*}"
  local tries=90
  while (( tries > 0 )); do
    st=$(sql "SELECT STATUS FROM oceanbase.DBA_OB_SERVERS WHERE SVR_IP='${ip}' LIMIT 1;" | tr -d '\r')
    if [[ "$st" == "active" || "$st" == "ACTIVE" ]]; then
      return 0
    fi
    sleep 5
    tries=$((tries-1))
  done
  return 1
}

echo "=== PRECHECK SERVERS ==="
sql "SELECT SVR_IP, SVR_PORT, ZONE, STATUS FROM oceanbase.DBA_OB_SERVERS ORDER BY SVR_IP;"
echo "=== PRECHECK TENANTS ==="
sql "SELECT tenant_name, status FROM oceanbase.DBA_OB_TENANTS ORDER BY tenant_name;"

for s in "${SERVERS[@]}"; do
  echo "=== RESTART SERVER ${s} ==="
  sql "ALTER SYSTEM STOP SERVER '${s}';"
  sleep 5
  sql "ALTER SYSTEM START SERVER '${s}';"
  echo "Waiting ${s} back to ACTIVE..."
  if wait_active "$s"; then
    echo "${s} ACTIVE"
  else
    echo "ERROR: ${s} did not return ACTIVE in time"
    sql "SELECT SVR_IP, SVR_PORT, ZONE, STATUS FROM oceanbase.DBA_OB_SERVERS ORDER BY SVR_IP;"
    exit 1
  fi
  sql "SELECT SVR_IP, SVR_PORT, ZONE, STATUS FROM oceanbase.DBA_OB_SERVERS ORDER BY SVR_IP;"
done

echo "=== POSTCHECK TENANTS ==="
sql "SELECT tenant_name, status FROM oceanbase.DBA_OB_TENANTS ORDER BY tenant_name;"