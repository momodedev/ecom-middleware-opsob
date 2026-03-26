#!/bin/bash
# Check OceanBase cluster status, tenant distribution, unit placement, and balance config
set -euo pipefail

OB_HOST=172.17.1.7
OB_PORT=2881
OB_USER="root@sys"
OB_PASS="OceanBase#!123"

ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no oceanadmin@${OB_HOST} "sudo su - admin -c '
source ~/.oceanbase-all-in-one/bin/env.sh
obclient -h127.0.0.1 -P${OB_PORT} -u${OB_USER} -p\"${OB_PASS}\" -Doceanbase -e \"
SELECT svr_ip, svr_port, zone, status, with_rootserver FROM __all_server;
SELECT tenant_id, tenant_name, primary_zone, locality FROM __all_tenant;
SELECT unit_id, resource_pool_id, svr_ip, zone FROM __all_unit;
SELECT name, value FROM __all_sys_parameter WHERE name IN (\\\"enable_rebalance\\\",\\\"balancer_idle_time\\\",\\\"resource_hard_limit\\\");
\"
'"
