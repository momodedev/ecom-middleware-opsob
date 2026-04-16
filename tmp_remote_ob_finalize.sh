#!/usr/bin/env bash
set -euo pipefail

OB_URL="https://obbusiness-private.oss-cn-shanghai.aliyuncs.com/download-center/opensource/oceanbase-all-in-one/8/x86_64/oceanbase-all-in-one-4.5.0_20260203.el8.x86_64.tar.gz"
OB_CLUSTER="ob_standalone"
OB_ROOT_PWD="OceanBase#!123"
OB_MEM="50G"

sudo bash -lc '
set -euo pipefail
mkdir -p /home/admin/ob-installer
cd /home/admin/ob-installer
if [ ! -f oceanbase-all-in-one.tar.gz ]; then
  wget -O oceanbase-all-in-one.tar.gz "'"${OB_URL}"'"
fi
if [ ! -d oceanbase-all-in-one ]; then
  tar -xf oceanbase-all-in-one.tar.gz -C /home/admin/ob-installer
fi
cd /home/admin/ob-installer/oceanbase-all-in-one
bash bin/install.sh
chown -R admin:admin /home/admin/ob-installer
'

sudo -iu admin bash -lc '
set -euo pipefail
/usr/bin/obd mirror clone /home/admin/ob-installer/oceanbase-all-in-one/rpms/*.rpm -f
/usr/bin/obd mirror disable remote
cat > ~/ob-standalone.yaml <<EOF
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
    memory_limit:   '"${OB_MEM}"'
    system_memory:  2G
    datafile_size:  50G
    log_disk_size:  50G
    cpu_count:      14
    root_password:  "'"${OB_ROOT_PWD}"'"
    production_mode: false
EOF
if /usr/bin/obd cluster list 2>/dev/null | grep -q '"${OB_CLUSTER}"'; then
  /usr/bin/obd cluster stop '"${OB_CLUSTER}"' || true
  /usr/bin/obd cluster destroy '"${OB_CLUSTER}"' -f || true
fi
/usr/bin/obd cluster deploy '"${OB_CLUSTER}"' -c ~/ob-standalone.yaml -y
/usr/bin/obd cluster start '"${OB_CLUSTER}"'
/usr/bin/obd cluster display '"${OB_CLUSTER}"'
'

ssh_test_cmd='sudo -iu admin bash -lc "mysql -h127.0.0.1 -P2881 -uroot@sys -p\"${OB_ROOT_PWD}\" -e \"select version();\""'
eval "$ssh_test_cmd"
ss -lntp | grep 2881 || true
