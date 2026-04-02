#!/usr/bin/env bash
set -euo pipefail
curl -sG "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=node_memory_MemTotal_bytes{job=\"node-exporter\"}/1024/1024/1024" | python3 -c 'import sys,json;d=json.load(sys.stdin);[print(r["metric"].get("instance"), round(float(r["value"][1]),2),"GiB") for r in d["data"]["result"]]'