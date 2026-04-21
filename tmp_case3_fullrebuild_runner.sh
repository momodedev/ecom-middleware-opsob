#!/usr/bin/env bash
set -Eeuo pipefail

mysql -h13.83.163.165 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -e "SET GLOBAL ob_query_timeout=30000000;"

export RUN_TIME=300
export WARMUP_TIME=120
export TABLES=90
export TABLE_SIZE=500000
export PREPARE_THREADS=30
export WORKLOADS='oltp_read_only oltp_read_write'
export THREADS_LIST='20 50 100 200'

bash ~/ecom-middleware-opsob/terraform/oceanbase_s/ansible/run_oceanbase_benchmark_nmysql_s.sh \
  tuned_case3_fullrebuild_20260417 \
  13.83.163.165 \
  root@sys \
  'OceanBase#!123' \
  sbtest \
  13.83.163.165
