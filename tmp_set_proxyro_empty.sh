#!/usr/bin/env bash
set -euo pipefail
mysql -h10.100.1.4 -P2881 -uroot@sys -p'OceanBase#!123' -e "ALTER USER proxyro IDENTIFIED BY '';"
mysql --connect-timeout=5 -h10.100.1.4 -P2881 -uproxyro@sys -e "select 1 as proxyro_no_pw_ok;"
