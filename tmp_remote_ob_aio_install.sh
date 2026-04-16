#!/usr/bin/env bash
set -euo pipefail

OB_URL="https://obbusiness-private.oss-cn-shanghai.aliyuncs.com/download-center/opensource/oceanbase-all-in-one/8/x86_64/oceanbase-all-in-one-4.5.0_20260203.el8.x86_64.tar.gz"
OB_CLUSTER="ob_standalone"
OB_ROOT_PWD="OceanBase#!123"
OB_MEM="50G"
OBD_DIR="$HOME/obd-install"

mkdir -p "$OBD_DIR"
cd "$OBD_DIR"

if [ ! -f oceanbase-all-in-one.tar.gz ]; then
  curl -fL "$OB_URL" -o oceanbase-all-in-one.tar.gz
fi

# Discover the extracted package directory even if archive root folder name changes.
if [ -z "$(find "$OBD_DIR" -maxdepth 2 -type f -name install.sh 2>/dev/null)" ]; then
  tar -xzf oceanbase-all-in-one.tar.gz
fi

INSTALL_DIR="$(dirname "$(find "$OBD_DIR" -maxdepth 2 -type f -name install.sh | head -n1)")"
if [ -z "$INSTALL_DIR" ] || [ ! -f "$INSTALL_DIR/install.sh" ]; then
  echo "ERROR: install.sh not found after extraction"
  exit 1
fi

if [ ! -x "$HOME/.oceanbase-all-in-one/bin/obd" ]; then
  cd "$INSTALL_DIR"
  bash install.sh
fi

source "$HOME/.oceanbase-all-in-one/bin/env.sh"
obd --version

cat > "$HOME/ob-standalone.yaml" <<EOF
oceanbase-ce:
  version: 4.5.0
  servers:
    - name: node1
      ip: 127.0.0.1
  global:
    home_path: /home/admin/oceanbase
    data_dir:  /oceanbase/data
    redo_dir:  /oceanbase/redo
    log_dir:   /var/log/oceanbase
    mysql_port: 2881
    rpc_port:   2882
    zone:       zone1
    cluster_id: 1
    memory_limit:   ${OB_MEM}
    system_memory:  2G
    datafile_size:  50G
    log_disk_size:  50G
    cpu_count:      14
    root_password:  "${OB_ROOT_PWD}"
    production_mode: false
EOF

if obd cluster list 2>/dev/null | grep -q "$OB_CLUSTER"; then
  obd cluster stop "$OB_CLUSTER" || true
  obd cluster destroy "$OB_CLUSTER" -f || true
fi

obd cluster deploy "$OB_CLUSTER" -c "$HOME/ob-standalone.yaml" -y
obd cluster start "$OB_CLUSTER"
obd cluster display "$OB_CLUSTER"

ss -lntp | grep 2881 || true
