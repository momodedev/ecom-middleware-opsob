# OceanBase Cluster Deployment on Azure

## 🎯 项目概述

本项目实现了在 Microsoft Azure 上自动化部署 **OceanBase 分布式数据库集群**，包括完整的监控和运维工具栈。

### 核心组件

- **Terraform**: Azure 基础设施即代码（IaC）
- **Ansible**: OceanBase 集群配置和部署
- **OceanBase**: 原生分布式数据库（4.3.5 版本）
- **Prometheus + Grafana**: 监控和可视化
- **OBD**: OceanBase Deployer 工具

## 📁 目录结构

```
ecom-middleware-opsob/
├── terraform/manage_node_ob/        # Terraform 配置（控制节点+OceanBase）
│   ├── main.tf                      # Azure 资源定义
│   ├── variables.tf                 # 变量定义（OceanBase 参数）
│   ├── secret.tfvars                # 配置模板
│   ├── provider.tf                  # Azure Provider
│   ├── outputs.tf                   # 输出定义
│   ├── cloud-init.tpl               # VM 初始化脚本
│   ├── deploy.sh                    # 部署辅助脚本
│   ├── import_existing.sh           # 导入现有资源脚本
│   ├── OCEANBASE_DEPLOYMENT_GUIDE.md  # 详细部署指南
│   └── BUGFIX_README.md             # 已知问题修复说明
│
├── ansible/
│   ├── playbooks/
│   │   └── deploy_oceanbase_playbook.yaml  # OceanBase 部署 playbook
│   ├── roles/
│   │   └── oceanbase/               # OceanBase Ansible role
│   │       ├── tasks/main.yml       # 部署任务
│   │       ├── templates/
│   │       │   ├── obcluster.yaml.j2  # 集群配置模板
│   │       │   └── prometheus_oceanbase_targets.json.j2
│   │       ├── defaults/main.yml    # 默认变量
│   │       └── handlers/main.yml    # 处理器
│   └── scripts/
│       └── oceanbase_health_check.sh  # 健康检查脚本
│
└── README.md                        # 本文件
```

## 🚀 快速开始

### 前置条件

1. **Azure 订阅**：有效的 Azure 订阅 ID
2. **SSH 密钥**：生成 SSH 密钥对
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
   ```
3. **本地工具**：
   - Azure CLI (`az login`)
   - Terraform v1.x+
   - Git

### 部署步骤

#### 1. 配置变量

编辑 `terraform/manage_node_ob/secret.tfvars`：

```hcl
ARM_SUBSCRIPTION_ID = "your-subscription-id-here"
resource_group_location = "westus"

# OceanBase 集群配置
oceanbase_instance_count    = 3
oceanbase_vm_size           = "Standard_D8s_v5"
oceanbase_data_disk_size_gb = 500
oceanbase_redo_disk_size_gb = 200

# OceanBase 参数
oceanbase_cluster_name      = "ob_cluster"
oceanbase_root_password     = "YourStrongPassword!123"
oceanbase_memory_limit      = "8G"
oceanbase_cpu_count         = 8

deploy_mode = "together"
```

#### 2. 执行部署

```bash
cd terraform/manage_node_ob

# 初始化 Terraform
terraform init

# 预览部署计划
terraform plan -var-file='secret.tfvars'

# 应用部署
terraform apply -var-file='secret.tfvars'
```

#### 3. 获取访问信息

```bash
# 获取控制节点公网 IP
CONTROL_IP=$(terraform output -raw control_public_ip)
echo "Control Node: $CONTROL_IP"

# 查看连接信息
terraform output
```

#### 4. 连接到控制节点

```bash
ssh -p 6666 azureadmin@$CONTROL_IP
```

#### 5. 验证部署

在控制节点上执行：

```bash
# 加载环境
source ~/.oceanbase-all-in-one/bin/env.sh

# 查看集群状态
obd cluster list

# 查看集群详情
obd cluster display ob_cluster

# 连接数据库
obclient -h127.0.0.1 -P2881 -uroot@sys -p'YourStrongPassword!123' -Doceanbase -A
```

## 📊 监控与运维

### 访问监控仪表板

1. **Grafana**: http://$CONTROL_IP:3000
   - 账号：`admin` / 密码：`admin`
   
2. **Prometheus**: http://$CONTROL_IP:9090

3. **OB-Dashboard**: http://$CONTROL_IP:2886
   - 账号：`root` / 密码：`YourStrongPassword!123`

### 运行健康检查

```bash
# 从本地
export CONTROL_IP=<control-ip>
cd ansible/scripts
./oceanbase_health_check.sh

# 或在控制节点
ssh -p 6666 azureadmin@$CONTROL_IP
cd ~/ecom-middleware-ops/ansible/scripts
./oceanbase_health_check.sh
```

## 🏗️ 架构设计

### 系统架构

```
Internet → Control Node (Public IP: 6666)
                    ↓
              VNet Peering
                    ↓
OceanBase Observers (3 nodes, Private IPs)
    ├── Zone 1: observer1 (2881, 2882, 2886)
    ├── Zone 2: observer2 (2881, 2882, 2886)
    └── Zone 3: observer3 (2881, 2882, 2886)
```

### 资源配置

| 组件 | 数量 | 规格 | 存储 |
|------|------|------|------|
| Control Node | 1 | D8ls_v6 (8vCPU, 32GB) | - |
| Observer Nodes | 3 | D8s_v5 (8vCPU, 32GB) | 500GB 数据 + 200GB 日志 |

### 端口规划

| 端口 | 服务 | 访问范围 |
|------|------|----------|
| 6666 | SSH (Control) | 公网 |
| 2881 | MySQL (Observer) | 内网 |
| 2882 | RPC (Observer) | 内网 |
| 2886 | OBShell | 内网 |
| 9090 | Prometheus | 公网 |
| 3000 | Grafana | 公网 |

## 📚 文档链接

- **[完整部署指南](OCEANBASE_DEPLOYMENT_GUIDE.md)** - 详细的部署、配置和运维文档
- **[Bug 修复说明](BUGFIX_README.md)** - Terraform 代码修复说明
- **[快速入门](QUICKSTART.md)** - Terraform 基础使用指南

## 🔧 常用命令

### 集群管理

```bash
# 查看集群列表
obd cluster list

# 显示集群详情
obd cluster display ob_cluster

# 重启集群
obd cluster restart ob_cluster

# 停止集群
obd cluster stop ob_cluster
```

### 数据库操作

```bash
# 连接数据库
obclient -h127.0.0.1 -P2881 -uroot@sys -p'password' -Doceanbase -A

# 创建租户
CREATE TENANT my_tenant 
  CHARSET='utf8mb4', 
  ZONE_LIST=('zone1','zone2','zone3'),
  RESOURCE_POOL_LIST=('my_pool');

# 查看服务器信息
SELECT * FROM oceanbase.__all_server;
```

## ⚠️ 重要提示

### 安全要求
- ✅ 修改所有默认密码
- ✅ 使用强密码策略
- ✅ 限制 NSG 访问规则
- ✅ 定期备份数据

### 性能建议
- ✅ 使用 Premium SSD
- ✅ 启用加速网络
- ✅ 监控磁盘使用率（<80%）
- ✅ 定期检查慢查询

### 高可用配置
- ✅ 至少 3 节点部署
- ✅ 跨可用区部署（如支持）
- ✅ 配置自动故障切换
- ✅ 定期测试恢复流程

## 🧹 清理资源

```bash
cd terraform/manage_node_ob
terraform destroy -var-file='secret.tfvars'
```

⚠️ **警告**：此操作将删除所有资源和数据！

## 📞 技术支持

如遇到问题，请收集以下信息：

1. 集群状态：`obd cluster display ob_cluster`
2. 错误日志：`tail -100 /oceanbase/log/observer.log`
3. 系统信息：`uname -a`, `cat /etc/os-release`
4. Terraform 输出：`terraform output`

## 📖 参考文档

- [OceanBase 官方文档](https://www.oceanbase.com/docs/)
- [OBD 使用指南](https://github.com/oceanbase/ob-deploy)
- [OceanBase 社区](https://ask.oceanbase.com/)

---

**版本**: OceanBase 4.3.5  
**最后更新**: 2026-03-20  
**状态**: ✅ 生产就绪
