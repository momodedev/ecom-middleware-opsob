#!/usr/bin/env bash
set -euo pipefail
for ip in 10.100.1.4 10.100.1.5 10.100.1.6; do
  echo "===== ${ip} ====="
  ok=0
  for u in oceanadmin azureadmin rockyadmin root; do
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no ${u}@${ip} 'echo user-ok:$(whoami) host:$(hostname)' 2>/dev/null; then
      ok=1
      break
    fi
  done
  if [[ $ok -eq 0 ]]; then
    echo "no-ssh-user-found"
  fi
  echo
 done