#!/bin/bash
for h in 10.100.1.4 10.100.1.5 10.100.1.6; do
  echo "==== $h ===="
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 oceanadmin@$h '
    echo HOST:$(hostname)
    ls -l /oceanbase/server/bin/observer 2>/dev/null || true
    ls -l /home/admin/oceanbase/bin/observer 2>/dev/null || true
    sudo systemctl list-unit-files | grep -Ei "observer|oceanbase|obshell" || true
    sudo systemctl status obshell --no-pager -l 2>/dev/null | head -20 || true
  ' || true
  echo
 done