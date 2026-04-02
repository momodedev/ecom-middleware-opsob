#!/usr/bin/env bash
set -euo pipefail
check_port() {
  local host="$1"; local port="$2"
  if timeout 2 bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1; then
    echo "${host}:${port} OK"
  else
    echo "${host}:${port} FAIL"
  fi
}
for ip in 172.17.1.5 172.17.1.6 172.17.1.7; do
  for p in 2881 2882 2883 2884; do
    check_port "$ip" "$p"
  done
done