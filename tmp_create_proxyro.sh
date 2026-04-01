#!/bin/bash
set -e
cat >/tmp/obproxy_user.sql <<'SQL'
CREATE USER IF NOT EXISTS proxyro@sys IDENTIFIED BY 'OceanBase#!123';
GRANT SELECT ON *.* TO proxyro@sys;
ALTER TENANT sys SET VARIABLES ob_tcp_invited_nodes='%';
SQL
mysql -h 10.100.1.4 -P 2881 -uroot@sys -pOceanBase#!123 < /tmp/obproxy_user.sql
mysql -h 10.100.1.4 -P 2881 -uroot@sys -pOceanBase#!123 -e "SHOW GRANTS FOR proxyro@sys;"