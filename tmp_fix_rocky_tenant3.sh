#!/bin/bash
HOST=172.17.1.6
PORT=2881
PASS='OceanBase#!123'

run_sys() {
  mysql -h "$HOST" -P "$PORT" -uroot@sys -p"$PASS" -Doceanbase "$@"
}

echo "===== 1. Check sbtest_tenant password hash ====="
run_sys -N -e "SELECT user_name, host, passwd FROM __all_virtual_user WHERE tenant_id=1002 AND user_name='root';" 2>&1

echo ""
echo "===== 2. Try empty password login ====="
mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -e "SELECT 1 AS ok;" 2>&1
echo "Empty pass RC=$?"

echo ""
echo "===== 3. If empty pass works, set password and variables ====="
mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -e "ALTER USER root IDENTIFIED BY '$PASS';" 2>&1
echo "Set password RC=$?"

echo ""
echo "===== 4. Login with new password ====="
mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -p"$PASS" -e "SELECT 1 AS ok;" 2>&1
echo "New pass RC=$?"

echo ""
echo "===== 5. Set tenant variables via whichever login works ====="
# Try with password first
mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -p"$PASS" -e "
SET GLOBAL ob_trx_timeout = 100000;
SET GLOBAL ob_trx_lock_timeout = 1000000;
" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "Password login failed, trying empty password..."
  mysql -h "$HOST" -P "$PORT" -u'root@sbtest_tenant' -e "
SET GLOBAL ob_trx_timeout = 100000;
SET GLOBAL ob_trx_lock_timeout = 1000000;
" 2>&1
  rc=$?
fi
echo "Set variables RC=$rc"

echo ""
echo "===== 6. Verify via sys tenant ====="
run_sys -e "SELECT name, value FROM __all_virtual_sys_variable WHERE tenant_id=1002 AND name IN ('ob_trx_timeout','ob_trx_lock_timeout');" 2>&1
