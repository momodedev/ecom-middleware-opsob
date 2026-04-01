#!/bin/bash
for h in 10.100.1.4 10.100.1.5 10.100.1.6; do
  echo "==== $h ===="
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 oceanadmin@$h '
    hostname
    sudo ss -lntp | grep -E "2881|2882|2886|9308" || true
    ps -ef | grep observer | grep -v grep || true
    sudo systemctl is-active observer 2>/dev/null || true
  ' || true
  echo
 done