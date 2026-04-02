#!/usr/bin/env bash
set -euo pipefail

echo "=== BEFORE: sbtest tenant unit config ==="
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "SELECT DISTINCT c.name, c.max_cpu, ROUND(c.memory_size/1024/1024/1024,2) AS mem_gb FROM oceanbase.DBA_OB_UNITS u JOIN oceanbase.DBA_OB_UNIT_CONFIGS c ON u.unit_config_id=c.unit_config_id JOIN oceanbase.DBA_OB_TENANTS t ON u.tenant_id=t.tenant_id WHERE t.tenant_name='sbtest_tenant';"

echo "=== BEFORE: Memory usage % ==="
curl -sG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=100*(1-node_memory_MemAvailable_bytes{job=\"node-exporter\"}/node_memory_MemTotal_bytes{job=\"node-exporter\"})" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["metric"].get("instance"), round(float(r["value"][1]),2)) for r in d["data"]["result"]]'

echo "=== BEFORE: MemAvailable GiB ==="
curl -sG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=node_memory_MemAvailable_bytes{job=\"node-exporter\"}/1024/1024/1024" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["metric"].get("instance"), round(float(r["value"][1]),2)) for r in d["data"]["result"]]'

echo "=== APPLY: set sbtest unit memory_size=20G ==="
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "ALTER RESOURCE UNIT sbtest_unit MEMORY_SIZE='20G';"

echo "=== AFTER APPLY: sbtest tenant unit config ==="
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "SELECT DISTINCT c.name, c.max_cpu, ROUND(c.memory_size/1024/1024/1024,2) AS mem_gb FROM oceanbase.DBA_OB_UNITS u JOIN oceanbase.DBA_OB_UNIT_CONFIGS c ON u.unit_config_id=c.unit_config_id JOIN oceanbase.DBA_OB_TENANTS t ON u.tenant_id=t.tenant_id WHERE t.tenant_name='sbtest_tenant';"

echo "Waiting 10 minutes for stabilization..."
sleep 600

echo "=== POST (10m): Memory usage % ==="
curl -sG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=100*(1-node_memory_MemAvailable_bytes{job=\"node-exporter\"}/node_memory_MemTotal_bytes{job=\"node-exporter\"})" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["metric"].get("instance"), round(float(r["value"][1]),2)) for r in d["data"]["result"]]'

echo "=== POST (10m): MemAvailable GiB ==="
curl -sG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=node_memory_MemAvailable_bytes{job=\"node-exporter\"}/1024/1024/1024" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["metric"].get("instance"), round(float(r["value"][1]),2)) for r in d["data"]["result"]]'