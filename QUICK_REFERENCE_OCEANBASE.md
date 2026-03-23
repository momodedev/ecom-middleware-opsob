# OceanBase 快速参考卡片 🚀

## 📋 连接信息模板

```bash
# 控制节点 SSH
ssh -p 6666 azureadmin@<CONTROL_IP>

# 数据库连接（在控制节点）
obclient -h127.0.0.1 -P2881 -uroot@sys -p'<PASSWORD>' -Doceanbase -A

# 数据库连接（从外部，需配置 NSG）
obclient -h<CONTROL_IP> -P2881 -uroot@sys -p'<PASSWORD>' -Doceanbase -A
```

## 🔑 默认端口

| 服务 | 端口 | 说明 |
|------|------|------|
| SSH (Control) | 6666 | 管理节点 SSH |
| MySQL Protocol | 2881 | OceanBase SQL 接口 |
| RPC Service | 2882 | Observer 内部通信 |
| OBShell | 2886 | OB 管理 Shell |
| Prometheus | 9090 | 监控指标收集 |
| Grafana | 3000 | 可视化仪表板 |

## 🎯 核心命令速查

### OBD 集群管理

```bash
source ~/.oceanbase-all-in-one/bin/env.sh

# 查看集群
obd cluster list

# 集群详情
obd cluster display <cluster_name>

# 部署集群
obd cluster deploy <cluster_name> -c /home/admin/obcluster.yaml

# 启动集群
obd cluster start <cluster_name>

# 停止集群
obd cluster stop <cluster_name>

# 重启集群
obd cluster restart <cluster_name>

# 销毁集群
obd cluster destroy <cluster_name>

# 编辑配置
obd cluster edit-config <cluster_name>
```

### SQL 常用查询

```sql
-- 查看服务器信息
SELECT * FROM oceanbase.__all_server;

-- 查看租户信息
SELECT TENANT_NAME, STATUS, PRIMARY_ZONE 
FROM oceanbase.DBA_OB_TENANTS;

-- 查看资源池
SELECT * FROM oceanbase.DBA_OB_RESOURCE_POOLS;

-- 查看活跃会话
SELECT SID, SERIAL#, USER, HOST, COMMAND, STATE 
FROM oceanbase.GV$OB_PROCESSLIST 
WHERE STATE != 'IDLE' 
LIMIT 10;

-- 查看 CPU 使用
SELECT SVR_IP, SVR_PORT, CPU_CAPACITY, CPU_TOTAL, CPU_ASSIGNED 
FROM oceanbase.GV$OB_SERVERS;

-- 查看内存使用
SELECT SVR_IP, MEMORY_CAPACITY, MEMORY_TOTAL, MEMORY_ASSIGNED, MEMORY_LIMIT 
FROM oceanbase.GV$OB_SERVERS;

-- 创建用户租户
CREATE TENANT IF NOT EXISTS app_tenant
  CHARSET='utf8mb4',
  ZONE_LIST=('zone1','zone2','zone3'),
  PRIMARY_ZONE='RANDOM',
  RESOURCE_POOL_LIST=('app_pool');

-- 创建数据库用户
CREATE USER 'app_user' IDENTIFIED BY 'StrongPassword123!';
GRANT ALL PRIVILEGES ON *.* TO 'app_user';

-- 删除租户
DROP TENANT <tenant_name>;
```

### 系统检查

```bash
# 磁盘使用
df -h /oceanbase
du -sh /oceanbase/*

# 内存使用
free -h

# CPU 信息
nproc
top -bn1 | head -20

# 网络连接
netstat -tlnp | grep -E ':(2881|2882|2886)'

# 查看日志
tail -100 /oceanbase/log/observer.log
tail -50 ~/.obd/log/obd.log

# LVM 状态
lvs
vgs
pvs
```

## 🔧 故障排查速查

### Observer 无法启动

```bash
# 1. 检查日志
tail -200 /oceanbase/log/observer.log | grep ERROR

# 2. 检查磁盘空间
df -h

# 3. 检查内存
free -h

# 4. 检查进程
ps aux | grep observer

# 5. 重启服务
obd cluster restart <cluster_name> --servers <server_name>
```

### 连接超时

```bash
# 1. 检查端口监听
netstat -tlnp | grep 2881

# 2. 检查防火墙
systemctl status firewalld

# 3. 检查 hosts
cat /etc/hosts | grep observer

# 4. 测试本地连接
obclient -h127.0.0.1 -P2881 -uroot@sys -p'password' -Doceanbase -A -e "SELECT 1"
```

### 性能问题

```sql
-- 查看慢查询
SELECT * FROM oceanbase.GV$OB_SQL_AUDIT 
WHERE ELAPSED_TIME > 1000000 
ORDER BY ELAPSED_TIME DESC 
LIMIT 10;

-- 查看锁等待
SELECT * FROM oceanbase.GV$OB_LOCK_WAIT;

-- 查看 I/O 等待
SELECT * FROM oceanbase.GV$OB_SYSTEM_EVENT 
WHERE EVENT LIKE '%wait%' 
ORDER BY TOTAL_WAITS DESC;
```

## 📊 监控指标

### Prometheus 查询示例

```promql
# Observer CPU 使用率
rate(process_cpu_seconds_total{job="oceanbase"}[5m])

# 内存使用
process_resident_memory_bytes{job="oceanbase"}

# 活跃会话数
ob_processlist_active{job="oceanbase"}

# QPS
rate(ob_sql_request_total{job="oceanbase"}[1m])

# 延迟
histogram_quantile(0.95, rate(ob_sql_request_duration_seconds_bucket{job="oceanbase"}[5m]))
```

### Grafana Dashboard ID

- OceanBase Overview: 自定义
- Tenant Metrics: 自定义
- Server Performance: 自定义

## 🛡️ 安全加固

### 修改默认密码

```sql
-- 修改 root 密码
ALTER USER root IDENTIFIED BY 'NewStrongPassword!123';

-- 修改 proxyro 密码
ALTER USER proxyro IDENTIFIED BY 'NewProxyPassword!456';
```

### 创建监控用户

```sql
CREATE USER 'monitor' IDENTIFIED BY 'MonitorPassword!789';
GRANT SELECT ON *.* TO 'monitor';
```

### 配置访问控制

```sql
-- 限制 IP 访问
CREATE USER 'app_user'@'10.0.%.%' IDENTIFIED BY 'password';

-- 撤销权限
REVOKE DELETE ON *.* FROM 'app_user';
```

## 💾 备份恢复

### 数据备份

```bash
# 设置备份路径
obd cluster edit-config <cluster_name>
# 添加：backup_destination = 'file:///oceanbase/backup'

# 执行全量备份
obclient -h127.0.0.1 -P2881 -uroot@sys -p'password' -Doceanbase -A -e \
  "ALTER SYSTEM BACKUP DATABASE FULL;"
```

### 恢复数据

```sql
-- 查看备份集
SELECT * FROM oceanbase.CDB_OB_BACKUP_SET_DETAILS;

-- 恢复到指定时间点
RESTORE DATABASE UNTIL TIME '2026-03-20 12:00:00';
```

## 📈 扩容操作

### 添加 Observer 节点

```bash
# 1. Terraform 增加节点数
oceanbase_instance_count = 6

# 2. 应用变更
terraform apply -var-file='secret.tfvars'

# 3. 添加到集群
obd cluster edit-config <cluster_name>
# 在 servers 列表中添加新节点

# 4. 重启集群
obd cluster restart <cluster_name>
```

### 升级资源配置

```sql
-- 修改 Zone 资源
ALTER SYSTEM MODIFY zone='zone1' 
SET cpu_count=16, memory_limit='16G';

-- 调整资源池
ALTER RESOURCE POOL pool1 UNIT='unit_config_name';
```

## 🎯 性能调优

### 系统参数调整

```sql
-- 调整写入速度
ALTER SYSTEM SET writing_throttling_maximum_duration='2h';

-- 调整合并时间
ALTER SYSTEM SET major_freeze_duty_time='02:00';

-- 开启并行查询
ALTER SYSTEM SET parallel_servers_target=64;
```

### SQL 优化

```sql
-- 查看执行计划
EXPLAIN SELECT * FROM table WHERE condition;

-- 分析表
ANALYZE TABLE table_name;

-- 创建索引
CREATE INDEX idx_name ON table_name(column_name);
```

## 🧹 日常维护

### 每日检查清单

- [ ] 检查集群状态：`obd cluster list`
- [ ] 查看错误日志：`tail -50 /oceanbase/log/observer.log`
- [ ] 检查磁盘空间：`df -h`
- [ ] 查看活跃会话：`SELECT COUNT(*) FROM GV$OB_PROCESSLIST`
- [ ] 检查备份状态：`SELECT * FROM CDB_OB_BACKUP_SET_DETAILS`

### 每周维护

- [ ] 清理过期日志
- [ ] 分析慢查询
- [ ] 检查资源使用趋势
- [ ] 验证备份完整性
- [ ] 更新统计信息

### 每月任务

- [ ] 性能基准测试
- [ ] 容量规划评估
- [ ] 安全审计
- [ ] 灾难恢复演练
- [ ] 文档更新

---

**版本**: 1.0  
**最后更新**: 2026-03-20  
**适用范围**: OceanBase 4.3.5 on Azure
