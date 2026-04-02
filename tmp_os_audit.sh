#!/usr/bin/env bash
set -euo pipefail

for ip in 172.17.1.5 172.17.1.6 172.17.1.7; do
  echo "============================"
  echo "NODE:$ip"
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no oceanadmin@"$ip" <<'EOS'
set -e
hostname
date -u

echo "---OS---"
egrep "^(NAME|VERSION|ID|VERSION_ID)=" /etc/os-release || true

echo "---KERNEL---"
uname -r

echo "---CPU---"
lscpu | egrep "Model name|CPU\(s\)|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)|NUMA node\(s\)" || true

echo "---MEM---"
free -h || true

echo "---DISK---"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT || true

echo "---FS---"
df -hT | egrep "Filesystem|/data|/|/var" || true

echo "---THP---"
cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true

echo "---SYSCTL---"
sysctl vm.swappiness net.core.somaxconn fs.file-max kernel.pid_max 2>/dev/null || true

echo "---LIMITS---"
ulimit -n || true

echo "---PROCESSES---"
pgrep -af observer || true
pgrep -af obproxy || true

echo "---PORTS---"
ss -lntp | egrep ":2881|:2882|:2883|:2884|:2885" || true
EOS
done
