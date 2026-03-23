#cloud-config
# Cloud-init configuration for Kafka broker VMs (Rocky Linux 9)
# Installs system dependencies needed before Ansible configures Kafka

package_update: true
package_upgrade: false

# Ensure required repositories are available before package install
bootcmd:
  - dnf -y install dnf-plugins-core || true
  - dnf config-manager --set-enabled crb || true
  - dnf -y install epel-release || true
  - dnf clean all || true
  - dnf makecache || true

packages:
  - dnf-plugins-core
  - jq
  - python3
  - python3-pip
  - python3-virtualenv
  - curl
  - wget
  - git
  - nc
  - tar
  - gzip
  - java-11-openjdk
  - java-11-openjdk-devel

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

  # Update package cache
  - dnf makecache || true
  
  # Create required directories with proper ownership
  - mkdir -p /opt/kafka
  - mkdir -p /data/kafka
  - mkdir -p /var/log/kafka
  
  # Create kafka user and group early (Ansible will reuse)
  - groupadd -f kafka || true
  - useradd -r -g kafka -s /bin/bash kafka || true
  
  # Format and mount data disk if attached (Supports SCSI and NVMe/PV2)
  - |
    DATA_DISK_DEVICE=""
    # Check LUN 0 (Standard Azure)
    if [ -e "/dev/disk/azure/scsi1/lun0" ]; then
      DATA_DISK_DEVICE=$(readlink -f /dev/disk/azure/scsi1/lun0)
    elif [ -b "/dev/sdc" ]; then
      DATA_DISK_DEVICE="/dev/sdc"
    else
      # Search for NVMe (Premium V2) - Find first unmounted NVMe disk
      for dev in /dev/nvme*n1; do
        if [ -b "$dev" ]; then
           # Check if device or its partitions are mounted
           if ! lsblk "$dev" -n -o MOUNTPOINT | grep -q "."; then
             DATA_DISK_DEVICE=$dev
             break
           fi
        fi
      done
    fi

    if [ -n "$DATA_DISK_DEVICE" ]; then
      if ! mountpoint -q /data/kafka; then
        echo "Formatting and mounting data disk: $DATA_DISK_DEVICE"
        mkfs.ext4 -F "$DATA_DISK_DEVICE" 2>/dev/null || true
        mount "$DATA_DISK_DEVICE" /data/kafka 2>/dev/null || true
        
        # Add to fstab using UUID
        UUID=$(blkid -s UUID -o value "$DATA_DISK_DEVICE")
        if [ -n "$UUID" ]; then
           if ! grep -q "$UUID" /etc/fstab; then
             echo "UUID=$UUID /data/kafka ext4 defaults,nofail 0 2" >> /etc/fstab
           fi
        else
           if ! grep -q "$DATA_DISK_DEVICE" /etc/fstab; then
             echo "$DATA_DISK_DEVICE /data/kafka ext4 defaults,nofail 0 2" >> /etc/fstab
           fi
        fi
        chmod 755 /data/kafka
        chown kafka:kafka /data/kafka
      fi
    fi
  
  # Set up Python environment for Ansible
  - python3 -m venv /home/${kafka_admin_username}/ansible-venv || true
  - /home/${kafka_admin_username}/ansible-venv/bin/pip install --upgrade pip setuptools
  - /home/${kafka_admin_username}/ansible-venv/bin/pip install ansible jinja2 netaddr
  - chmod -R 755 /home/${kafka_admin_username}/ansible-venv
  
  # Set up system limits for Kafka
  - |
    cat >> /etc/security/limits.conf << 'EOF'
    *       soft    nofile   65536
    *       hard    nofile   65536
    *       soft    nproc    65536
    *       hard    nproc    65536
    EOF
  
  # Configure kernel parameters for Kafka performance
  - |
    cat >> /etc/sysctl.conf << 'EOF'
    # Network tuning
    net.core.rmem_max = 134217728
    net.core.wmem_max = 134217728
    net.ipv4.tcp_rmem = 4096 87380 67108864
    net.ipv4.tcp_wmem = 4096 65536 67108864
    net.ipv4.tcp_max_syn_backlog = 1024
    net.ipv4.ip_local_port_range = 1024 65535
    EOF
  # Apply sysctl but ignore missing parameters (some may not exist on all kernel versions)
  - sysctl -p || true
  
  # Log cloud-init completion
  - echo "Cloud-init bootstrap completed at $(date)" > /var/log/kafka-bootstrap-complete.log

  # Upgrade Rocky Linux to latest 9.x (targeting 9.7) before handing over to Ansible
  - dnf -y upgrade --refresh
  - dnf clean all || true

power_state:
  delay: now
  mode: reboot
  message: "Rebooting after Rocky Linux system update"
  timeout: 60
  condition: true
