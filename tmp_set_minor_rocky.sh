#!/bin/bash
PASS='OceanBase#!123'

echo "===== Rocky Cluster ====="
mysql -h 172.17.1.6 -P 2881 -u'root@sbtest_tenant' -p"$PASS" -e "ALTER SYSTEM SET minor_compact_trigger = 16;" 2>&1
echo "Rocky minor_compact_trigger=16 RC=$?"

# Verify
mysql -h 172.17.1.6 -P 2881 -uroot@sys -p"$PASS" -Doceanbase -e "SHOW PARAMETERS LIKE 'minor_compact_trigger'\G" 2>&1 | grep -E "name|value|zone" | head -12
