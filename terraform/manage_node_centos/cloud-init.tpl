#cloud-config
# Cloud-init configuration for control node initialization (Rocky Linux 9)
# Azure-native bootstrap template for Terraform, Ansible, and Azure CLI setup

package_update: true
package_upgrade: false

bootcmd:
  - dnf -y install dnf-plugins-core || true
  - dnf config-manager --set-enabled crb || true
  - dnf -y install epel-release || true
  - dnf clean all || true
  - dnf makecache || true

packages:
  - jq
  - python3
  - python3-pip
  - python3-virtualenv
  - policycoreutils-python-utils
  - curl
  - wget
  - gnupg

runcmd:
  # Ignore Azure SR-IOV NIC drivers that are transparently bonded to synthetic NICs
  - mkdir -p /etc/NetworkManager/conf.d
  - |
    cat > /etc/NetworkManager/conf.d/99-azure-unmanaged-devices.conf <<'EOF'
    # Ignore SR-IOV interface on Azure, since it is transparently bonded
    # to the synthetic interface
    [keyfile]
    unmanaged-devices=driver:mana;driver:mlx4_core;driver:mlx5_core
    EOF
  - systemctl restart NetworkManager || true

  # Configure SSH daemon to use custom port for control node access
  - sed -i -E 's/^#?Port[[:space:]]+[0-9]+/Port ${control_ssh_port}/' /etc/ssh/sshd_config
  - grep -q '^Port ${control_ssh_port}$' /etc/ssh/sshd_config || echo 'Port ${control_ssh_port}' >> /etc/ssh/sshd_config
  - restorecon -Rv /etc/ssh >/dev/null 2>&1 || true
  - semanage port -a -t ssh_port_t -p tcp ${control_ssh_port} >/dev/null 2>&1 || semanage port -m -t ssh_port_t -p tcp ${control_ssh_port} >/dev/null 2>&1 || true
  - systemctl restart sshd

  # Disable firewalld to ensure Prometheus/Grafana ports are accessible
  - systemctl disable firewalld
  - systemctl stop firewalld
  
  # Install Terraform from HashiCorp repo (Rocky Linux)
  - dnf install -y dnf-plugins-core
  - dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
  - dnf install -y terraform
  
  # Install Azure CLI (Rocky Linux)
  - rpm --import https://packages.microsoft.com/keys/microsoft.asc
  - echo "[azure-cli]" | tee /etc/yum.repos.d/azure-cli.repo
  - echo "name=Azure CLI" | tee -a /etc/yum.repos.d/azure-cli.repo
  - echo "baseurl=https://packages.microsoft.com/yumrepos/azure-cli" | tee -a /etc/yum.repos.d/azure-cli.repo
  - echo "enabled=1" | tee -a /etc/yum.repos.d/azure-cli.repo
  - echo "gpgcheck=1" | tee -a /etc/yum.repos.d/azure-cli.repo
  - echo "gpgkey=https://packages.microsoft.com/keys/microsoft.asc" | tee -a /etc/yum.repos.d/azure-cli.repo
  - dnf install -y azure-cli
  
  # Setup Ansible venv as azureadmin user
  - su - azureadmin -c 'python3 -m venv /home/azureadmin/ansible-venv'
  - su - azureadmin -c '/home/azureadmin/ansible-venv/bin/pip install ansible'
  - su - azureadmin -c '/home/azureadmin/ansible-venv/bin/ansible-galaxy collection install azure.azcollection --force'
  - su - azureadmin -c '/home/azureadmin/ansible-venv/bin/pip install -r /home/azureadmin/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt'
  
  # Generate SSH key for azureadmin (skip if exists)
  - su - azureadmin -c 'test -f /home/azureadmin/.ssh/id_rsa || ssh-keygen -t rsa -N "" -f /home/azureadmin/.ssh/id_rsa'
  
  # Login to Azure using managed identity (control node has Contributor role)
  - su - azureadmin -c 'az login --identity'

  # Upgrade Rocky Linux to latest 9.x (targeting 9.7) after tools are installed
  - dnf -y upgrade --refresh
  - dnf clean all || true
  
  # Signal completion
  - touch /var/lib/cloud/instance/control-node-initialized

write_files:
  - path: /etc/profile.d/ansible-env.sh
    permissions: '0644'
    content: |
      # Auto-activate Ansible venv for azureadmin
      if [ "$USER" = "azureadmin" ] && [ -f "$HOME/ansible-venv/bin/activate" ]; then
        source "$HOME/ansible-venv/bin/activate"
      fi

final_message: "Control node initialization complete after $UPTIME seconds"

power_state:
  delay: now
  mode: reboot
  message: "Rebooting control node after Rocky Linux system update"
  timeout: 60
  condition: true
