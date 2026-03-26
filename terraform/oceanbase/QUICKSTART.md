# OceanBase 一键自动化部署 - 快速参考指南

## 🚀 一条命令完成全部部署

```bash
cd terraform/oceanbase
./deploy.sh
```

**或者使用 Terraform 原生命令：**

```bash
cd terraform/oceanbase
terraform init
terraform apply -var-file='secret.tfvars'
```

## ⏱️ 部署时间

- **基础设施**: ~10-15 分钟
- **OceanBase 集群**: ~15-20 分钟
- **监控工具**: ~5 分钟
- **总计**: ~30-45 分钟

## 📋 部署流程（自动执行）

### 阶段 1: Azure 基础设施
✅ 创建资源组 `control-ob-rg`  
✅ 创建 VNet `oceanbase-vnet` (10.1.0.0/16)  
✅ 创建 Subnet (10.1.1.0/24)  
✅ 创建 NSG 并配置安全规则  
✅ 创建 NAT Gateway  
✅ 创建 3 台 Observer VM (Standard_D8s_v5)  
✅ 挂载数据盘 (500GB SSD)  
✅ 挂载日志盘 (500GB SSD)  

### 阶段 2: 等待与验证
⏳ 等待 60 秒让 VM 初始化  
🔍 验证所有 VM 的 SSH 连接  
✅ 生成 Ansible inventory 文件  

### 阶段 3: OceanBase 部署（Ansible）
🔧 系统参数调优（limits.conf, sysctl.conf）  
📦 安装 OceanBase all-in-one 包  
🔐 配置 SSH 信任关系  
📝 生成集群配置文件  
🚀 使用 OBD 部署集群  
✅ 启动集群服务  

### 阶段 4: 监控部署（Ansible）
📊 部署 Prometheus  
📈 部署 Grafana  
🎯 生成服务发现配置  
✅ 配置 OceanBase Dashboard  

### 阶段 5: 输出信息
📄 显示连接信息  
📄 显示监控访问地址  
📄 显示下一步操作指南  

## 📊 部署完成后

### 获取访问信息
```bash
# 查看部署摘要
terraform output deployment_summary

# 查看连接信息
terraform output oceanbase_connection_info

# 查看监控访问
terraform output monitoring_urls
```

### 连接到 OceanBase
```bash
# 获取第一个 observer IP
OBSERVER_IP=$(terraform output -json observer_private_ips | jq -r '.[0]')

# SSH 连接
ssh -i ~/.ssh/id_ed25519 oceanadmin@$OBSERVER_IP

# 切换到 admin 用户
su - admin

# 加载环境
source ~/.oceanbase-all-in-one/bin/env.sh

# 查看集群
obd cluster list
obd cluster display ob_cluster

# 数据库连接
obclient -h127.0.0.1 -P2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -A
```

### 访问监控
- **Grafana**: http://\<control-node-public-ip\>:3000
  - 账号：`admin`
  - 密码：`admin`
  
- **Prometheus**: http://\<control-node-public-ip\>:9090

## 🔧 故障排查

### 查看部署日志
```bash
# Terraform 部署日志会自动显示

# Ansible 日志在 /tmp/ansible*.log

# OceanBase 日志
tail -f /oceanbase/data/log/observer.log
```

### 重新运行 Ansible
```bash
cd ../../ansible_ob
source ~/ansible-venv/bin/activate
ansible-playbook -i inventory/oceanbase_hosts_auto playbooks/deploy_oceanbase_playbook.yaml
```

### 重新部署监控
```bash
ansible-playbook -i inventory/control_node playbooks/deploy_monitoring_playbook.yml
```

## ⚠️ 重要提示

1. **密码安全**: 首次登录后立即修改默认密码
2. **凭证保护**: secret.tfvars 包含敏感信息，切勿提交到 Git
3. **备份策略**: 定期备份重要数据
4. **监控告警**: 配置关键指标告警规则

## 📞 技术支持

- OceanBase 文档：https://www.oceanbase.com/docs/
- 社区论坛：https://ask.oceanbase.com/
- 项目 Issues: GitHub
