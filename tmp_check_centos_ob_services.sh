#!/usr/bin/env bash
set -euo pipefail
for ip in 10.100.1.4 10.100.1.5 10.100.1.6; do
  echo "================ ${ip} ================"
  ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no oceanadmin@${ip} '
    echo "host=$(hostname)"
    echo "-- os --"
    cat /etc/centos-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || true
    echo "-- processes --"
    ps -ef | egrep "[o]bserver|[o]bproxy|[o]bshell" || true
    echo "-- listen ports 2881/2882/2883/2884/2886 --"
    ss -lntp 2>/dev/null | egrep ":2881|:2882|:2883|:2884|:2886" || true
    echo "-- candidate dirs --"
    ls -ld /home/oceanbase/oceanbase /home/oceanbase/obproxy /data/1/oceanbase 2>/dev/null || true
  '
  echo
 done