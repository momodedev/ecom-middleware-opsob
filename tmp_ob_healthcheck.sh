#!/usr/bin/env bash
set -euo pipefail

echo "=== SQL health check ==="
obclient -h127.0.0.1 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -A -e "select version(); show databases;"

echo "=== Cluster display ==="
/usr/bin/obd cluster display ob_standalone

echo "=== Port listener ==="
ss -lntp | grep 2881 || true
