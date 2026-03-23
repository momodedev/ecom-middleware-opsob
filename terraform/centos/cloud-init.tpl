#cloud-config
# Cloud-init bootstrap for CentOS 7.9 Kafka broker VMs.
# Uses yum (not dnf) – CentOS 7 ships with yum, not dnf.
# Java 11 (OpenJDK) is installed here; Ansible installs Kafka 2.3.1 afterwards.

package_update: true
package_upgrade: false

bootcmd:
  # Ensure Azure DNS first so yum repos can resolve.
  - printf "nameserver 168.63.129.16\nnameserver 1.1.1.1\n" > /etc/resolv.conf

  # CentOS 7 mirrorlist endpoints are often unavailable; pin to vault.
  - |
    for f in /etc/yum.repos.d/*.repo; do
      mv "$f" "$f.disabled" || true
    done
    cat > /etc/yum.repos.d/CentOS-Vault.repo <<'EOF'
    [base]
    name=CentOS-7.9.2009 - Base
    baseurl=http://vault.centos.org/7.9.2009/os/$basearch/
    gpgcheck=1
    enabled=1
    gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

    [updates]
    name=CentOS-7.9.2009 - Updates
    baseurl=http://vault.centos.org/7.9.2009/updates/$basearch/
    gpgcheck=1
    enabled=1
    gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

    [extras]
    name=CentOS-7.9.2009 - Extras
    baseurl=http://vault.centos.org/7.9.2009/extras/$basearch/
    gpgcheck=1
    enabled=1
    gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
    EOF

  # EPEL provides python3-pip and extra packages needed for Ansible venv
  - yum -y install epel-release 2>/dev/null || true
  - yum clean all 2>/dev/null || true
  - yum makecache 2>/dev/null || true

packages:
  - epel-release
  - java-11-openjdk
  - java-11-openjdk-devel
  - python3
  - python3-pip
  - git
  - curl
  - wget
  - nmap-ncat
  - tar
  - gzip
  - jq
  - net-tools

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

  - yum makecache || true

  # Create standard Kafka directories
  - mkdir -p /opt/kafka /data/kafka /var/log/kafka

  # Dedicated kafka service account (Ansible role expects it to exist)
  - groupadd -f kafka || true
  - id kafka 2>/dev/null || useradd -r -g kafka -s /bin/bash kafka

  # ── Format and mount the attached Premium SSD data disk (LUN 0) ─────────
  - |
    DATA_DISK_DEVICE=""
    # Azure standard LUN 0 path
    if [ -e "/dev/disk/azure/scsi1/lun0" ]; then
      DATA_DISK_DEVICE=$(readlink -f /dev/disk/azure/scsi1/lun0)
    elif [ -b "/dev/sdc" ]; then
      DATA_DISK_DEVICE="/dev/sdc"
    else
      # NVMe fallback (Premium SSD v2)
      for dev in /dev/nvme*n1; do
        if [ -b "$dev" ] && ! lsblk "$dev" -n -o MOUNTPOINT | grep -q .; then
          DATA_DISK_DEVICE="$dev"
          break
        fi
      done
    fi
    if [ -n "$DATA_DISK_DEVICE" ] && ! mountpoint -q /data/kafka; then
      mkfs.ext4 -F "$DATA_DISK_DEVICE" || true
      mount "$DATA_DISK_DEVICE" /data/kafka || true
      UUID=$(blkid -s UUID -o value "$DATA_DISK_DEVICE")
      if [ -n "$UUID" ] && ! grep -q "$UUID" /etc/fstab; then
        echo "UUID=$UUID /data/kafka ext4 defaults,nofail 0 2" >> /etc/fstab
      fi
      chown kafka:kafka /data/kafka
    fi

  # ── Python 3 virtual environment for Ansible ────────────────────────────
  # python3 -m venv is built-in for Python 3.6+ (no extra package needed)
  - python3 -m venv /home/${kafka_admin_username}/ansible-venv || true
  - /home/${kafka_admin_username}/ansible-venv/bin/pip install --upgrade pip setuptools
  - /home/${kafka_admin_username}/ansible-venv/bin/pip install ansible jinja2 netaddr
  - chown -R ${kafka_admin_username}:${kafka_admin_username} /home/${kafka_admin_username}/ansible-venv || true

  # ── File descriptor and process limits for Kafka brokers ─────────────────
  - |
    cat >> /etc/security/limits.conf << 'EOF'
    *       soft    nofile   128000
    *       hard    nofile   128000
    *       soft    nproc    128000
    *       hard    nproc    128000
    EOF

  # ── Kernel network/VM tuning for Kafka ───────────────────────────────────
  - |
    cat >> /etc/sysctl.conf << 'EOF'
    net.core.rmem_max = 134217728
    net.core.wmem_max = 134217728
    net.ipv4.tcp_rmem = 4096 87380 67108864
    net.ipv4.tcp_wmem = 4096 65536 67108864
    net.core.netdev_max_backlog = 5000
    net.ipv4.ip_local_port_range = 1024 65535
    vm.swappiness = 1
    vm.dirty_ratio = 60
    vm.dirty_background_ratio = 5
    EOF
  - sysctl -p || true

  # ── Signal bootstrap complete (Ansible readiness checks look for this) ────
  - echo "CentOS 7.9 cloud-init bootstrap completed at $(date)" > /var/log/kafka-bootstrap-complete.log
