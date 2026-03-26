#!/bin/bash
set -euo pipefail

if [ "$#" -lt 5 ]; then
  echo "Usage: $0 <cluster_label> <mysql_host> <mysql_user> <mysql_password_or_dash> <mysql_db> [inventory_file]"
  echo "Example (quoted password): $0 d8s_v6 172.17.1.6 root@sys 'OceanBase#!123' sbtest inventory/oceanbase_hosts"
  echo "Example (env password): OCEANBASE_BENCH_PASSWORD='OceanBase#!123' $0 d8s_v6 172.17.1.6 root@sys - sbtest inventory/oceanbase_hosts"
  exit 1
fi

CLUSTER_LABEL="$1"
MYSQL_HOST="$2"
MYSQL_USER="$3"
MYSQL_PASSWORD_ARG="$4"
MYSQL_DB="$5"
INVENTORY_FILE="${6:-inventory/oceanbase_hosts}"

if [ "$MYSQL_PASSWORD_ARG" = "-" ]; then
  MYSQL_PASSWORD="${OCEANBASE_BENCH_PASSWORD:-}"
  if [ -z "$MYSQL_PASSWORD" ]; then
    read -r -s -p "Enter MySQL password: " MYSQL_PASSWORD
    echo ""
  fi
else
  MYSQL_PASSWORD="$MYSQL_PASSWORD_ARG"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_ROOT="$(dirname "$SCRIPT_DIR")"

if [[ "$INVENTORY_FILE" = /* ]]; then
  INVENTORY_PATH="$INVENTORY_FILE"
else
  INVENTORY_PATH="$ANSIBLE_ROOT/$INVENTORY_FILE"
fi

if [ ! -f "$INVENTORY_PATH" ]; then
  echo "Error: inventory file not found: $INVENTORY_PATH"
  echo "Hint: use path relative to ansible_ob, e.g. inventory/oceanbase_hosts"
  exit 1
fi

cd "$ANSIBLE_ROOT"

echo "Using inventory: $INVENTORY_PATH"
echo "Using ansible root: $ANSIBLE_ROOT"

ansible-playbook -i "$INVENTORY_PATH" playbooks/benchmark_oceanbase_sysbench.yml \
  -e "benchmark_label=$CLUSTER_LABEL" \
  -e "mysql_host=$MYSQL_HOST" \
  -e "mysql_user=$MYSQL_USER" \
  -e "mysql_password=$MYSQL_PASSWORD" \
  -e "mysql_db=$MYSQL_DB"

echo "Benchmark finished. CSV: /tmp/oceanbase-bench/${CLUSTER_LABEL}.csv"
