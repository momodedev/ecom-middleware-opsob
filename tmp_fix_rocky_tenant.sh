#!/bin/bash
HOST=172.17.1.6
PORT=2881

# Try common passwords
for P in '' 'OceanBase#!123' 'oceanbase' 'root'; do
  echo "Trying password: '$P'"
  mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -p"$P" -e "SELECT 1 AS ok;" 2>&1
  if [ $? -eq 0 ]; then
    echo "SUCCESS with password: '$P'"
    
    # Set the tenant variables
    mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -p"$P" -e "SET GLOBAL ob_trx_timeout = 100000;"
    echo "ob_trx_timeout RC=$?"
    
    mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -p"$P" -e "SET GLOBAL ob_trx_lock_timeout = 1000000;"
    echo "ob_trx_lock_timeout RC=$?"
    
    # Verify
    mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -p"$P" -e "SHOW GLOBAL VARIABLES LIKE 'ob_trx_timeout'; SHOW GLOBAL VARIABLES LIKE 'ob_trx_lock_timeout';"
    
    break
  fi
done
