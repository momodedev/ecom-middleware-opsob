#!/usr/bin/env bash
set -euo pipefail

Q1='100*(1-node_memory_MemAvailable_bytes{job="node-exporter"}/node_memory_MemTotal_bytes{job="node-exporter"})'
Q2='node_memory_MemAvailable_bytes{job="node-exporter"}/1024/1024/1024'
Q3='node_memory_Cached_bytes{job="node-exporter"}/1024/1024/1024'

echo "=== MEM USAGE % ==="
curl -sG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=${Q1}" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["metric"].get("instance"), round(float(r["value"][1]),2)) for r in d["data"]["result"]]'

echo "=== MEM AVAILABLE GiB ==="
curl -sG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=${Q2}" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["metric"].get("instance"), round(float(r["value"][1]),2)) for r in d["data"]["result"]]'

echo "=== CACHED GiB ==="
curl -sG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=${Q3}" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["metric"].get("instance"), round(float(r["value"][1]),2)) for r in d["data"]["result"]]'

echo "=== OCEANBASE MEMORY PARAMS ==="
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "select svr_ip, name, value from oceanbase.GV\$OB_PARAMETERS where name in ('memory_limit_percentage','memory_limit','system_memory');"

echo "=== TENANT UNIT MEMORY (sbtest_tenant) ==="
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "SELECT z.name, uc.max_cpu, ROUND(uc.memory_size/1024/1024/1024,2) AS memory_gb FROM oceanbase.__all_unit u JOIN oceanbase.__all_resource_pool p ON u.resource_pool_id=p.resource_pool_id JOIN oceanbase.__all_unit_config uc ON u.unit_config_id=uc.unit_config_id JOIN oceanbase.__all_zone z ON u.zone=z.name WHERE p.tenant_id=(SELECT tenant_id FROM oceanbase.__all_tenant WHERE tenant_name='sbtest_tenant') ORDER BY z.name;"