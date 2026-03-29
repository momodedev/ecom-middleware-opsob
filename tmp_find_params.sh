#!/bin/bash
PASS='OceanBase#!123'
run_sys() {
  mysql -h 10.100.1.6 -P 2881 -uroot@sys -p"$PASS" -Doceanbase "$@"
}
echo "=== fine_grained ==="
run_sys -N -e "SHOW PARAMETERS LIKE '%fine_grained%';" 2>&1
echo "=== elr ==="
run_sys -N -e "SHOW PARAMETERS LIKE '%elr%';" 2>&1
echo "=== lock params ==="
run_sys -N -e "SHOW PARAMETERS LIKE '%lock%';" 2>&1 | head -20
echo "=== enable_early ==="
run_sys -N -e "SHOW PARAMETERS LIKE '%early%';" 2>&1
echo "=== hidden _ob ==="
run_sys -N -e "SHOW PARAMETERS LIKE '_ob%';" 2>&1 | head -20
echo "=== hidden _ ==="
run_sys -N -e "SHOW PARAMETERS LIKE '_%';" 2>&1 | head -40
