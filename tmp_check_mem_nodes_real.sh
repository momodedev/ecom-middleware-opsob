#!/usr/bin/env bash
set -euo pipefail
for ip in 172.17.1.5 172.17.1.6 172.17.1.7; do
  echo "===== NODE ${ip} ====="
  ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no azureadmin@${ip} '
    hostname
    date
    echo "-- free -h --"
    free -h
    echo "-- key meminfo --"
    awk "/MemTotal|MemAvailable|Cached|Buffers|SReclaimable|Shmem|SwapTotal|SwapFree/ {print}" /proc/meminfo
    echo "-- observer/obproxy rss --"
    ps -eo pid,user,comm,%mem,rss,vsz,args --sort=-rss | grep -E "observer|obproxy" | head -n 20 || true
    echo "-- top rss --"
    ps -eo pid,user,comm,%mem,rss,vsz --sort=-rss | head -n 15
    echo "-- vmstat sample --"
    vmstat 1 3 | tail -n 1
  '
  echo
 done