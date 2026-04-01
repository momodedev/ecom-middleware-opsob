#!/bin/bash
set -e
cat >/tmp/obproxy_user_fix.sql <<'SQL'
CREATE USER IF NOT EXISTS 'proxyro'@'%' IDENTIFIED BY 'OceanBase#!123';
GRANT SELECT ON *.* TO 'proxyro'@'%';
SQL
mysql -h 10.100.1.4 -P 2881 -uroot@sys -pOceanBase#!123 < /tmp/obproxy_user_fix.sql
mysql -h 10.100.1.4 -P 2881 -uroot@sys -pOceanBase#!123 -e "SHOW GRANTS FOR 'proxyro'@'%';"