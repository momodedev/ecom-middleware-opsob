#!/usr/bin/env bash
# deploy.sh – provision infrastructure and deploy OceanBase Standalone
# Run from the terraform/oceanbase_s directory.
set -euo pipefail

TF_DIR="$(cd "$(dirname "$0")" && pwd)"
ANSIBLE_DIR="${TF_DIR}/ansible"
TFVARS="${TF_DIR}/secret.tfvars"

echo "=== Step 1: Terraform init + apply ==="
cd "${TF_DIR}"
terraform init
terraform plan -var-file="${TFVARS}" -out=tfplan
terraform apply tfplan

echo ""
echo "=== Step 2: Capture public IP and build Ansible inventory ==="
PUBLIC_IP=$(terraform output -raw public_ip_address)
SSH_KEY=$(terraform output -raw ssh_command | awk '{print $3}' | sed 's/-i//' | xargs)
ANSIBLE_PORT=${ANSIBLE_PORT:-22}

cat > "${ANSIBLE_DIR}/inventory.ini" <<INI
[ob_standalone]
${PUBLIC_IP} ansible_user=azureadmin ansible_port=${ANSIBLE_PORT} ansible_ssh_private_key_file=${SSH_KEY}

[ob_standalone:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ob_admin_username=admin
ob_cluster_name=ob_standalone
ob_root_password=OceanBase#!123
ob_memory_limit=50G
INI

echo "Inventory written to ${ANSIBLE_DIR}/inventory.ini"

echo ""
echo "=== Step 3: Run Ansible playbook ==="
cd "${ANSIBLE_DIR}"
ansible-playbook -i inventory.ini playbook.yml

echo ""
echo "=== Deployment complete ==="
echo "Connect: mysql -h${PUBLIC_IP} -P2881 -uroot@sys -p"
