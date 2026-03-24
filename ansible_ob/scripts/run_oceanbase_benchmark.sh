#!/bin/bash
set -euo pipefail

if [ "$#" -lt 5 ]; then
  echo "Usage: $0 <cluster_label> <mysql_host> <mysql_user> <mysql_password> <mysql_db> [inventory_file]"
  echo "Example: $0 d8s_v6 172.17.1.6 root@sys 'OceanBase#!123' sbtest inventory/oceanbase_hosts_auto"
  exit 1
fi

CLUSTER_LABEL="$1"
MYSQL_HOST="$2"
MYSQL_USER="$3"
MYSQL_PASSWORD="$4"
MYSQL_DB="$5"
INVENTORY_FILE="${6:-inventory/oceanbase_hosts_auto}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$ANSIBLE_ROOT"

ansible-playbook -i "$INVENTORY_FILE" playbooks/benchmark_oceanbase_sysbench.yml \
  -e "benchmark_label=$CLUSTER_LABEL" \
  -e "mysql_host=$MYSQL_HOST" \
  -e "mysql_user=$MYSQL_USER" \
  -e "mysql_password=$MYSQL_PASSWORD" \
  -e "mysql_db=$MYSQL_DB"

echo "Benchmark finished. CSV: /tmp/oceanbase-bench/${CLUSTER_LABEL}.csv"
