# OceanBase Cluster Deployment on Azure

## 📋 概述

本项目实现了在 Microsoft Azure 上自动化部署 OceanBase 分布式数据库集群，包括完整的监控和运维工具栈。

## 🏗️ 架构设计

### 系统架构

```
Internet → Control Node (Public IP)
                    ↓
              VNet Peering
                    ↓
OceanBase Observers (3 nodes, Private IPs)
    ├── Zone 1: ob-observer-0 (2881-MySQL, 2882-RPC, 2886-Shell)
    ├── Zone 2: ob-observer-1 (2881-MySQL, 2882-RPC, 2886-Shell)
    └── Zone 3: ob-observer-2 (2881-MySQL, 2882-RPC, 2886-Shell)
                    ↓
            NAT Gateway → Internet
```

### 组件说明

| 组件 | 数量 | 规格 | 用途 |
|------|------|------|------|
| **Observer Nodes** | 3 | Standard_D8s_v5 | OceanBase 数据库节点 |
| **数据盘** | 3 | 500GB Premium SSD | 数据存储 |
| **日志盘** | 3 | 200GB Premium SSD | Redo 日志存储 |
| **VNet** | 1 | 10.1.0.0/16 | 私有网络 |
| **NAT Gateway** | 1 | - | 出站访问 |

### 端口规划

| 端口 | 协议 | 用途 | 访问范围 |
|------|------|------|----------|
| 2881 | TCP | MySQL 协议 (Observer) | 内网 |
| 2882 | TCP | RPC 服务 (Observer) | 内网 |
| 2886 | TCP | OBShell (Observer) | 内网 |
| 22 | TCP | SSH | 内网 |
| 9100 | TCP | Node Exporter | 内网 |
| 9308 | TCP | OceanBase Exporter | 内网 |

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
   - jq (用于脚本处理)

### 部署步骤

#### 1. 配置环境变量

编辑 `terraform/oceanbase/secret.tfvars` 文件：

```hcl
# Azure 订阅 ID（必需）
ARM_SUBSCRIPTION_ID = "your-subscription-id-here"

# 资源组配置
resource_group_name       = "oceanbase-cluster"
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

# 网络配置
enable_nat_gateway          = true
enable_availability_zones   = true
enable_vnet_peering         = true

# 部署模式
deploy_mode                 = "separate"  # 或 "together"
```

#### 2. 初始化 Terraform

```bash
cd terraform/oceanbase

# 初始化 Terraform
terraform init

# 预览部署计划
terraform plan -var-file='secret.tfvars'

# 执行部署
terraform apply -var-file='secret.tfvars'
```

**部署时间**：约 10-15 分钟

#### 3. 生成 Ansible Inventory

```bash
# 返回项目根目录
cd ../../ansible

# 运行 inventory 生成脚本
./scripts/generate_oceanbase_inventory.sh

# 查看生成的 inventory
cat inventory/oceanbase_hosts
```

#### 4. 部署 OceanBase 集群

```bash
# 激活 Ansible 虚拟环境（如果有）
source ~/ansible-venv/bin/activate

# 验证 SSH 连接
ansible all -i inventory/oceanbase_hosts -m ping

# 部署 OceanBase 集群
ansible-playbook -i inventory/oceanbase_hosts playbooks/deploy_oceanbase_cluster.yml
```

**部署时间**：约 15-20 分钟

#### 5. 验证部署

SSH 到任意 observer 节点：

```bash
# 获取 observer IP
OBSERVER_IP=$(terraform output -json observer_private_ips | jq -r '.[0]')

# SSH 到 observer
ssh -i ~/.ssh/id_ed25519 oceanadmin@$OBSERVER_IP

# 切换到 admin 用户
su - admin

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

### Prometheus 配置

部署脚本会自动生成 Prometheus 服务发现配置：

```bash
# 查看生成的 targets
sudo cat /etc/prometheus/file_sd/oceanbase_targets.json
```

### Grafana Dashboard

通过控制节点访问 Grafana（如果已部署）：

- URL: `http://<control-node-ip>:3000`
- 账号：`admin`
- 密码：`admin`（首次登录需修改）

## 🔧 运维操作

### 扩缩容

#### 扩展节点

```bash
# 1. 修改 secret.tfvars 增加 oceanbase_instance_count
# 2. 重新应用 Terraform
terraform apply -var-file='secret.tfvars'

# 3. 重新生成 inventory
./scripts/generate_oceanbase_inventory.sh

# 4. 重新运行 Ansible playbook
ansible-playbook -i inventory/oceanbase_hosts playbooks/deploy_oceanbase_cluster.yml
```

#### 缩减节点

```bash
# 1. 停止要移除的节点上的 OceanBase
obd cluster stop ob_cluster

# 2. 从集群删除节点
obd cluster edit-config ob_cluster
# 删除对应节点配置

# 3. 修改 terraform 减少节点数
# 4. 重新应用
terraform apply -var-file='secret.tfvars'
```

### 备份恢复

#### 数据备份

```sql
-- 创建备份用户
CREATE USER 'backup_user'@'%' IDENTIFIED BY 'BackupPassword123!';
GRANT SELECT ON *.* TO 'backup_user'@'%';

-- 使用 mysqldump 备份
mysqldump -h127.0.0.1 -P2881 -ubackup_user -p --all-databases > backup.sql
```

### 故障排查

#### 查看 OceanBase 日志

```bash
# Observer 日志
tail -f /oceanbase/data/log/observer.log

# RootService 日志
tail -f /oceanbase/data/log/rootservice.log
```

#### 检查集群状态

```bash
source ~/.oceanbase-all-in-one/bin/env.sh
obd cluster display ob_cluster
```

#### 重启集群

```bash
# 停止集群
obd cluster stop ob_cluster

# 启动集群
obd cluster start ob_cluster
```

## 📝 输出变量

Terraform 部署完成后会输出以下信息：

```bash
# 查看输出
terraform output

# 获取 observer IP 列表
terraform output -json observer_private_ips

# 获取 VM 名称
terraform output -json observer_vm_names

# 获取连接信息
terraform output oceanbase_connection_info
```

## ⚠️ 注意事项

1. **密码安全**：务必修改默认密码 `OceanBase#!123`
2. **网络访问**：确保 allowed_cidrs 配置正确
3. **磁盘性能**：使用 Premium SSD 保证性能
4. **可用区**：生产环境建议启用可用区
5. **备份策略**：定期备份重要数据

## 📚 参考文档

- [OceanBase 官方文档](https://www.oceanbase.com/docs/)
- [OceanBase GitHub](https://github.com/oceanbase/oceanbase)
- [OBD 使用指南](https://github.com/oceanbase/obdeploy)

## 🆘 技术支持

遇到问题时：

1. 查看 OceanBase 日志
2. 检查集群状态
3. 访问 [OceanBase 社区论坛](https://ask.oceanbase.com/)
4. 查阅项目文档
