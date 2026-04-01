#!/bin/bash
for h in 10.100.1.4 10.100.1.5 10.100.1.6; do
  echo "==== $h ===="
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 oceanadmin@$h '
    ls -l /oceanbase/server/bin | egrep "observer|obshell|start|stop" || true
    ls -l /oceanbase/server/etc | head -40 || true
  ' || true
  echo
 done