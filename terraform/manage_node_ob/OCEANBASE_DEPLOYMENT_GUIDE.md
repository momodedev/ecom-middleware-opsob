# OceanBase 集群 Azure 部署指南

## 📋 概述

本项目实现了在 Microsoft Azure 上自动化部署OceanBase 分布式数据库集群，包括完整的监控和运维工具栈。

## 🏗️ 架构设计

### 系统架构
```
Internet → Control Node (Public IP: 6666)
                    ↓
              VNet Peering
                    ↓
OceanBase Observers (3 nodes, Private IPs)
    ├── Zone 1: observer1 (2881-MySQL, 2882-RPC, 2886-Shell)
    ├── Zone 2: observer2 (2881-MySQL, 2882-RPC, 2886-Shell)
    └── Zone 3: observer3 (2881-MySQL, 2882-RPC, 2886-Shell)
                    ↓
            NAT Gateway → Internet
```

### 组件说明

| 组件 | 数量 | 规格 | 用途 |
|------|------|------|------|
| **Control Node** | 1 | Standard_D8ls_v6 | 管理节点，部署OBD、OCP-Express |
| **Observer Nodes** | 3 | Standard_D8s_v5 | OceanBase数据库节点 |
| **数据盘** | 3 | 500GB SSD | 数据存储 |
| **日志盘** | 3 | 200GB SSD | Redo 日志存储 |

### 端口规划

| 端口 | 协议 | 用途 | 访问范围 |
|------|------|------|----------|
| 6666 | TCP | SSH (Control Node) | 公网 |
| 2881 | TCP | MySQL 协议 (Observer) | 内网 |
| 2882 | TCP | RPC 服务 (Observer) | 内网 |
| 2886 | TCP | OBShell (Observer) | 内网 |
| 9090 | TCP | Prometheus | 公网 |
| 3000 | TCP | Grafana | 公网 |

## 🚀 快速开始

### 前置要求

1. **Azure 订阅**：有效的 Azure 订阅
2. **SSH 密钥**：ED25519 或 RSA 密钥对
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
   ```
3. **本地工具**：
   - Azure CLI
   - Terraform v1.x+
   - Git

### 部署步骤

#### 1. 配置环境变量

编辑 `secret.tfvars` 文件：

```hcl
# Azure 订阅 ID（必需）
ARM_SUBSCRIPTION_ID = "your-subscription-id-here"

# 资源组配置
resource_group_name       = "control-ob-rg"
resource_group_location   = "westus"

# OceanBase 集群配置
oceanbase_instance_count    = 3  # 建议 3 节点实现高可用
oceanbase_vm_size           = "Standard_D8s_v5"
oceanbase_data_disk_size_gb = 500
oceanbase_redo_disk_size_gb = 200

# OceanBase 参数
oceanbase_cluster_name      = "ob_cluster"
oceanbase_root_password     = "OceanBase#!123"  # 请修改为强密码
oceanbase_memory_limit      = "8G"
oceanbase_cpu_count         = 8

# 部署模式
deploy_mode = "together"  # "together" 或 "separate"
```

#### 2. 初始化并部署

```bash
cd terraform/manage_node_ob

# 初始化 Terraform
terraform init

# 预览部署计划
terraform plan -var-file='secret.tfvars'

# 执行部署
terraform apply -var-file='secret.tfvars'
```

**部署时间**：约 15-20 分钟

#### 3. 获取访问信息

```bash
# 获取控制节点公网 IP
CONTROL_IP=$(terraform output -raw control_public_ip)
echo "Control Node IP: $CONTROL_IP"

# 获取 OceanBase 连接信息
terraform output oceanbase_connection_info
```

#### 4. 连接到控制节点

```bash
# SSH 到控制节点
ssh -p 6666 azureadmin@$CONTROL_IP
```

#### 5. 验证部署

在控制节点上执行：

```bash
# 加载 OceanBase 环境
source ~/.oceanbase-all-in-one/bin/env.sh

# 查看集群列表
obd cluster list

# 查看集群详情
obd cluster display ob_cluster

# 测试数据库连接
obclient -h127.0.0.1 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -A

# 执行 SQL 查询
MySQL [oceanbase]> SELECT * FROM oceanbase.__all_server;
```

## 📊 监控与运维

### 访问监控仪表板

1. **Grafana** (http://$CONTROL_IP:3000)
   - 默认账号：`admin`
   - 默认密码：`admin`（首次登录需修改）
   - OceanBase Dashboard: `/d/oceanbase`

2. **Prometheus** (http://$CONTROL_IP:9090)
   - 指标查询和告警管理

3. **OB-Dashboard** (http://$CONTROL_IP:2886)
   - OceanBase 专用监控界面
   - 账号：`root`
   - 密码：`OceanBase#!123`

### 健康检查

运行健康检查脚本：

```bash
# 从本地运行
cd ansible/scripts
export CONTROL_IP=<control-node-ip>
./oceanbase_health_check.sh

# 或在控制节点上运行
ssh -p 6666 azureadmin@$CONTROL_IP
cd ~/ecom-middleware-ops/ansible/scripts
./oceanbase_health_check.sh
```

### 常用运维命令

#### 集群管理

```bash
# 查看集群状态
obd cluster list

# 查看集群详情
obd cluster display <cluster_name>

# 停止集群
obd cluster stop <cluster_name>

# 启动集群
obd cluster start <cluster_name>

# 删除集群
obd cluster destroy <cluster_name>
```

#### 租户管理

```bash
# 连接到 OceanBase
obclient -h127.0.0.1 -P2881 -uroot@sys -p'password' -Doceanbase -A

# 创建用户租户
CREATE TENANT IF NOT EXISTS my_tenant 
  CHARSET='utf8mb4', 
  ZONE_LIST=('zone1', 'zone2', 'zone3'),
  PRIMARY_ZONE='RANDOM',
  RESOURCE_POOL_LIST=('my_pool');

# 查看租户信息
SELECT * FROM oceanbase.DBA_OB_TENANTS;
```

#### 性能监控

```bash
# 查看 CPU 使用率
obclient -h127.0.0.1 -P2881 -uroot@sys -p'password' -Doceanbase -A -e \
  "SELECT * FROM oceanbase.GV$OB_SERVERS ORDER BY cpu_total DESC;"

# 查看内存使用
obclient -h127.0.0.1 -P2881 -uroot@sys -p'password' -Doceanbase -A -e \
  "SELECT * FROM oceanbase.GV$OB_SERVERS ORDER BY memory_total DESC;"

# 查看活跃会话
obclient -h127.0.0.1 -P2881 -uroot@sys -p'password' -Doceanbase -A -e \
  "SELECT * FROM oceanbase.GV$OB_PROCESSLIST WHERE STATE != 'IDLE' LIMIT 10;"
```

## 🔧 故障排查

### 常见问题

#### 1. Observer 节点无法启动

**症状**：`obd cluster list` 显示节点状态为 `inactive`

**解决方案**：
```bash
# 检查日志
tail -100 /oceanbase/log/observer.log

# 检查磁盘空间
df -h /oceanbase

# 检查内存
free -h

# 重启节点
obd cluster restart <cluster_name> --servers <server_name>
```

#### 2. 无法连接到数据库

**症状**：obclient 连接超时

**解决方案**：
```bash
# 检查端口监听
netstat -tlnp | grep 2881

# 检查防火墙
systemctl status firewalld

# 检查 hosts 配置
cat /etc/hosts

# 测试本地连接
obclient -h127.0.0.1 -P2881 -uroot@sys -p'password' -Doceanbase -A
```

#### 3. 监控服务异常

**症状**：Grafana 或 Prometheus 无法访问

**解决方案**：
```bash
# 检查服务状态
systemctl status prometheus
systemctl status grafana-server

# 重启服务
sudo systemctl restart prometheus
sudo systemctl restart grafana-server

# 查看日志
journalctl -u prometheus -f
journalctl -u grafana-server -f
```

## 🎯 最佳实践

### 性能优化

1. **磁盘配置**
   - 使用 Premium SSD 或 Ultra Disk
   - 数据和日志分离存储
   - 定期清理过期的 syslog

2. **内存配置**
   - 设置合理的 `memory_limit`（建议物理内存的 70-80%）
   - 调整 `system_memory` 满足系统需求
   - 监控内存使用率，避免 swap

3. **网络优化**
   - 确保 Observer 节点间低延迟（<1ms）
   - 使用加速网络（Accelerated Networking）
   - 配置合适的 TCP 参数

### 安全加固

1. **访问控制**
   - 修改默认密码
   - 限制 NSG 入站规则
   - 使用 SSH 密钥认证

2. **备份策略**
   - 配置定期备份
   - 启用增量备份
   - 测试恢复流程

3. **审计日志**
   - 开启 SQL 审计
   - 保留足够的日志历史
   - 集中日志管理

## 📈 扩容指南

### 水平扩容（增加 Observer 节点）

```bash
# 1. 在 Terraform 中增加节点数
oceanbase_instance_count = 6  # 从 3 增加到 6

# 2. 应用变更
terraform apply -var-file='secret.tfvars'

# 3. 添加新节点到集群
obd cluster edit-config <cluster_name>
# 在配置文件中添加新 server 信息

# 4. 重启集群使配置生效
obd cluster restart <cluster_name>
```

### 垂直扩容（升级 VM 规格）

```bash
# 1. 修改 VM 规格
oceanbase_vm_size = "Standard_D16s_v5"

# 2. 应用变更（会重启 VM）
terraform apply -var-file='secret.tfvars'

# 3. 更新 OceanBase 资源配置
obclient -h127.0.0.1 -P2881 -uroot@sys -p'password' -Doceanbase -A -e \
  "ALTER SYSTEM MODIFY zone='zone1' SET cpu_count=16, memory_limit='16G';"
```

## 🧹 清理资源

### 销毁整个部署

```bash
cd terraform/manage_node_ob
terraform destroy -var-file='secret.tfvars'
```

⚠️ **警告**：此操作将删除所有资源和数据！

### 部分清理

```bash
# 只删除 OceanBase 集群
ssh -p 6666 azureadmin@$CONTROL_IP
source ~/.oceanbase-all-in-one/bin/env.sh
obd cluster destroy ob_cluster

# 在 Terraform 中移除相关资源
# 然后执行
terraform apply -var-file='secret.tfvars'
```

## 📚 参考文档

- [OceanBase 官方文档](https://www.oceanbase.com/docs/)
- [OBD 使用指南](https://github.com/oceanbase/ob-deploy)
- [OceanBase社区论坛](https://ask.oceanbase.com/)
- [Prometheus 监控](https://prometheus.io/docs/)
- [Grafana 文档](https://grafana.com/docs/)

## 🤝 技术支持

如遇到问题，请收集以下信息：

1. **集群状态**：`obd cluster display <cluster_name>`
2. **错误日志**：`/oceanbase/log/observer.log`
3. **系统信息**：`uname -a`, `cat /etc/os-release`
4. **网络配置**：`ifconfig`, `route -n`
5. **Terraform 输出**：`terraform output`

---

**最后更新**: 2026-03-20  
**版本**: OceanBase 4.3.5  
**状态**: ✅ 生产就绪
