#!/usr/bin/env bash
set -euo pipefail

cat > "$HOME/ob-standalone.yaml" <<'EOF'
oceanbase-ce:
  version: 4.5.0.0
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
    memory_limit:   50G
    system_memory:  2G
    datafile_size:  50G
    log_disk_size:  50G
    cpu_count:      14
    root_password:  "OceanBase#!123"
    production_mode: false
EOF

/usr/bin/obd cluster deploy ob_standalone -c "$HOME/ob-standalone.yaml"
