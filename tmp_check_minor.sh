#!/bin/bash
PASS='OceanBase#!123'
mysql -h 10.100.1.6 -P 2881 -uroot@sys -p"$PASS" -Doceanbase -e "SHOW PARAMETERS LIKE 'minor_compact_trigger'\G" 2>&1
