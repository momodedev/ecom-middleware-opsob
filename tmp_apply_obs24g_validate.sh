#!/usr/bin/env bash
set -euo pipefail

echo "=== BEFORE: memory_limit params ==="
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "SELECT svr_ip, value FROM oceanbase.GV\$OB_PARAMETERS WHERE name='memory_limit' ORDER BY svr_ip;"

echo "=== BEFORE: Memory usage % ==="
curl -sG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=100*(1-node_memory_MemAvailable_bytes{job=\"node-exporter\"}/node_memory_MemTotal_bytes{job=\"node-exporter\"})" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["metric"].get("instance"), round(float(r["value"][1]),2)) for r in d["data"]["result"]]'

echo "=== BEFORE: MemAvailable GiB ==="
curl -sG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=node_memory_MemAvailable_bytes{job=\"node-exporter\"}/1024/1024/1024" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["metric"].get("instance"), round(float(r["value"][1]),2)) for r in d["data"]["result"]]'

echo "=== APPLY: set memory_limit=24G per observer ==="
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "ALTER SYSTEM SET memory_limit='24G' SERVER='172.17.1.5:2882';"
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "ALTER SYSTEM SET memory_limit='24G' SERVER='172.17.1.6:2882';"
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "ALTER SYSTEM SET memory_limit='24G' SERVER='172.17.1.7:2882';"

echo "=== AFTER APPLY: memory_limit params ==="
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "SELECT svr_ip, value FROM oceanbase.GV\$OB_PARAMETERS WHERE name='memory_limit' ORDER BY svr_ip;"

echo "Waiting 5 minutes for stabilization..."
sleep 300

echo "=== POST: Memory usage % ==="
curl -sG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=100*(1-node_memory_MemAvailable_bytes{job=\"node-exporter\"}/node_memory_MemTotal_bytes{job=\"node-exporter\"})" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["metric"].get("instance"), round(float(r["value"][1]),2)) for r in d["data"]["result"]]'

echo "=== POST: MemAvailable GiB ==="
curl -sG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=node_memory_MemAvailable_bytes{job=\"node-exporter\"}/1024/1024/1024" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["metric"].get("instance"), round(float(r["value"][1]),2)) for r in d["data"]["result"]]'

run_case() {
  local mode="$1"
  local lua="$2"
  local out="/tmp/${mode}_post_obs24g.out"
  echo "=== BENCH ${mode} (threads=100,time=60s) ==="
  sysbench "$lua" \
    --db-driver=mysql \
    --mysql-host=172.17.1.7 \
    --mysql-port=2883 \
    --mysql-user='root@sbtest_tenant#ob_cluster' \
    --mysql-password='OceanBase#!123' \
    --mysql-db=sbtest \
    --tables=10 \
    --table-size=100000 \
    --threads=100 \
    --time=60 \
    --report-interval=10 \
    run | tee "$out"
  echo "--- ${mode} summary ---"
  awk '/transactions:/{tps=$3} /95th percentile:/{p95=$3} END{printf("TPS=%s P95ms=%s\n",tps,p95)}' "$out"
}

run_case "read_only" "/usr/share/sysbench/oltp_read_only.lua"
run_case "read_write" "/usr/share/sysbench/oltp_read_write.lua"