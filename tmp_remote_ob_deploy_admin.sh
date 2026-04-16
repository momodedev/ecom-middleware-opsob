#!/usr/bin/env bash
set -euo pipefail

OB_CLUSTER="ob_standalone"
OB_ROOT_PWD="OceanBase#!123"
OB_MEM="50G"

/usr/bin/obd mirror clone /home/admin/ob-installer/oceanbase-all-in-one/rpms/*.rpm -f
/usr/bin/obd mirror disable remote

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

if /usr/bin/obd cluster list 2>/dev/null | grep -q "$OB_CLUSTER"; then
  /usr/bin/obd cluster stop "$OB_CLUSTER" || true
  /usr/bin/obd cluster destroy "$OB_CLUSTER" -f || true
fi

/usr/bin/obd cluster deploy "$OB_CLUSTER" -c "$HOME/ob-standalone.yaml" -y
/usr/bin/obd cluster start "$OB_CLUSTER"
/usr/bin/obd cluster display "$OB_CLUSTER"

mysql -h127.0.0.1 -P2881 -uroot@sys -p"$OB_ROOT_PWD" -e "select version();"
ss -lntp | grep 2881 || true
