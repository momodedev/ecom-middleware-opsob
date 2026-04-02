#!/usr/bin/env bash
set -euo pipefail
mysql -h172.17.1.7 -P2883 -uroot@sys#ob_cluster -p"OceanBase#!123" -Nse "DESC oceanbase.DBA_OB_SERVERS;"