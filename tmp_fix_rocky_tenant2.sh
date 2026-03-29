#!/bin/bash
HOST=172.17.1.6
PORT=2881
PASS='OceanBase#!123'

run_sys() {
  mysql -h "$HOST" -P "$PORT" -uroot@sys -p"$PASS" -Doceanbase "$@"
}

echo "===== Check current tenant config ====="
run_sys -e "SELECT tenant_id, tenant_name FROM __all_tenant WHERE tenant_name='sbtest_tenant';"

echo ""
echo "===== Reset sbtest_tenant root password via sys ====="
# In OB 4.x, reset tenant password via ALTER USER in sys
run_sys -e "ALTER USER root@'%' IDENTIFIED BY '$PASS' TENANT sbtest_tenant;" 2>&1
echo "RC=$?"

# Alternative syntax
run_sys -e "ALTER USER 'root'@'%' IDENTIFIED BY '$PASS' /*tenant=sbtest_tenant*/;" 2>&1
echo "ALT RC=$?"

sleep 2
echo ""
echo "===== Test login ====="
mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -p"$PASS" -e "SELECT 1 AS login_ok;" 2>&1
echo "RC=$?"

echo ""
echo "===== Set tenant variables ====="
mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -p"$PASS" -e "SET GLOBAL ob_trx_timeout = 100000;" 2>&1
echo "ob_trx_timeout RC=$?"

mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -p"$PASS" -e "SET GLOBAL ob_trx_lock_timeout = 1000000;" 2>&1
echo "ob_trx_lock_timeout RC=$?"

echo ""
echo "===== Verify ====="
mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -p"$PASS" -e "SHOW GLOBAL VARIABLES LIKE 'ob_trx_timeout'; SHOW GLOBAL VARIABLES LIKE 'ob_trx_lock_timeout';" 2>&1
