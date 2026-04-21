#!/usr/bin/env bash
set -Eeuo pipefail

HOST="13.83.163.165"
PORT="2881"
USER="root@sys"
PASS="OceanBase#!123"
DB="sbtest"
TABLES=90
TABLE_SIZE=500000
PREPARE_THREADS=10

base=(
  sysbench
  --db-driver=mysql
  --mysql-host="${HOST}"
  --mysql-port="${PORT}"
  --mysql-user="${USER}"
  --mysql-password="${PASS}"
  --mysql-db="${DB}"
  --tables="${TABLES}"
  --table-size="${TABLE_SIZE}"
  --events=0
  --report-interval=5
  --db-ps-mode=disable
)

echo "[prepare-only] set global timeout to 60s"
mysql -h"${HOST}" -P"${PORT}" -u"${USER}" -p"${PASS}" -Doceanbase -e "SET GLOBAL ob_query_timeout=60000000;"

echo "[prepare-only] cleanup old sbtest tables"
"${base[@]}" --threads=5 oltp_read_only cleanup || true

echo "[prepare-only] preparing ${TABLES} tables x ${TABLE_SIZE} rows with ${PREPARE_THREADS} threads"
"${base[@]}" --threads="${PREPARE_THREADS}" oltp_read_only prepare

echo "[prepare-only] done"
