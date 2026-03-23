#cloud-config
# Cloud-init configuration for OceanBase observer VMs (Rocky Linux 9)
# Installs system dependencies needed before Ansible configures OceanBase

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
  - openssl
  - sshpass
  - rsync
  - lsof
  - sysstat
  - iotop

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
  - mkdir -p /data/oceanbase
  - mkdir -p /data/oceanbase/observer
  - mkdir -p /data/oceanbase/clog
  - mkdir -p /data/oceanbase/slog
  - mkdir -p /var/log/oceanbase
  - mkdir -p /home/${oceanbase_admin_username}/.ssh
  
  # Set up SSH directory permissions
  - chmod 700 /home/${oceanbase_admin_username}/.ssh
  
  # Create oceanbase user and group early (Ansible will reuse)
  - groupadd -f oceanbase || true
  - useradd -r -g oceanbase -s /bin/bash oceanbase || true
  
  # Create oceanadmin user if different from oceanbase
  - if [ "${oceanbase_admin_username}" != "oceanbase" ]; then
      groupadd -f ${oceanbase_admin_username} || true
      useradd -r -g ${oceanbase_admin_username} -s /bin/bash ${oceanbase_admin_username} || true
      chmod 700 /home/${oceanbase_admin_username}/.ssh
    fi
  
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
      if ! mountpoint -q /data/oceanbase; then
        echo "Formatting and mounting data disk: $DATA_DISK_DEVICE"
        mkfs.ext4 -F "$DATA_DISK_DEVICE" 2>/dev/null || true
        mount "$DATA_DISK_DEVICE" /data/oceanbase 2>/dev/null || true
        
        # Add to fstab using UUID
        UUID=$(blkid -s UUID -o value "$DATA_DISK_DEVICE")
        if [ -n "$UUID" ]; then
           if ! grep -q "$UUID" /etc/fstab; then
             echo "UUID=$UUID /data/oceanbase ext4 defaults,nofail 0 2" >> /etc/fstab
           fi
        else
           if ! grep -q "$DATA_DISK_DEVICE" /etc/fstab; then
             echo "$DATA_DISK_DEVICE /data/oceanbase ext4 defaults,nofail 0 2" >> /etc/fstab
           fi
        fi
        chmod 755 /data/oceanbase
        chown oceanbase:oceanbase /data/oceanbase
        chown oceanbase:oceanbase /data/oceanbase/observer
        chown oceanbase:oceanbase /data/oceanbase/slog
      fi
    fi
  
  # Format and mount redo log disk if attached
  - |
    REDO_DISK_DEVICE=""
    # Check LUN 1 (Standard Azure)
    if [ -e "/dev/disk/azure/scsi1/lun1" ]; then
      REDO_DISK_DEVICE=$(readlink -f /dev/disk/azure/scsi1/lun1)
    elif [ -b "/dev/sdd" ]; then
      REDO_DISK_DEVICE="/dev/sdd"
    else
      # Search for second NVMe disk
      nvme_count=0
      for dev in /dev/nvme*n1; do
        if [ -b "$dev" ]; then
          nvme_count=$((nvme_count + 1))
          if [ $nvme_count -eq 2 ] && ! lsblk "$dev" -n -o MOUNTPOINT | grep -q "."; then
            REDO_DISK_DEVICE=$dev
            break
          fi
        fi
      done
    fi

    if [ -n "$REDO_DISK_DEVICE" ]; then
      if ! mountpoint -q /data/oceanbase/clog; then
        echo "Formatting and mounting redo log disk: $REDO_DISK_DEVICE"
        mkfs.ext4 -F "$REDO_DISK_DEVICE" 2>/dev/null || true
        mount "$REDO_DISK_DEVICE" /data/oceanbase/clog 2>/dev/null || true
        
        # Add to fstab using UUID
        UUID=$(blkid -s UUID -o value "$REDO_DISK_DEVICE")
        if [ -n "$UUID" ]; then
           if ! grep -q "$UUID" /etc/fstab; then
             echo "UUID=$UUID /data/oceanbase/clog ext4 defaults,nofail 0 2" >> /etc/fstab
           fi
        else
           if ! grep -q "$REDO_DISK_DEVICE" /etc/fstab; then
             echo "$REDO_DISK_DEVICE /data/oceanbase/clog ext4 defaults,nofail 0 2" >> /etc/fstab
           fi
        fi
        chown oceanbase:oceanbase /data/oceanbase/clog
      fi
    fi
  
  # Set up Python environment for Ansible
  - python3 -m venv /home/${oceanbase_admin_username}/ansible-venv || true
  - /home/${oceanbase_admin_username}/ansible-venv/bin/pip install --upgrade pip setuptools
  - /home/${oceanbase_admin_username}/ansible-venv/bin/pip install ansible jinja2 netaddr paramiko
  - chmod -R 755 /home/${oceanbase_admin_username}/ansible-venv
  - chown -R ${oceanbase_admin_username}:${oceanbase_admin_username} /home/${oceanbase_admin_username}/ansible-venv
  
  # Set up system limits for OceanBase
  - |
    cat >> /etc/security/limits.conf << 'EOF'
    *       soft    nofile   65536
    *       hard    nofile   65536
    *       soft    nproc    65536
    *       hard    nproc    65536
    oceanbase       soft    nofile   1048576
    oceanbase       hard    nofile   1048576
    oceanbase       soft    nproc    65536
    oceanbase       hard    nproc    65536
    EOF
  
  # Configure kernel parameters for OceanBase performance
  - |
    cat >> /etc/sysctl.conf << 'EOF'
    # Network tuning
    net.core.rmem_max = 134217728
    net.core.wmem_max = 134217728
    net.ipv4.tcp_rmem = 4096 87380 67108864
    net.ipv4.tcp_wmem = 4096 65536 67108864
    net.ipv4.tcp_max_syn_backlog = 1024
    net.ipv4.ip_local_port_range = 1024 65535
    net.core.netdev_max_backlog = 65536
    net.ipv4.route.flush = 1
    
    # Memory tuning for OceanBase
    vm.swappiness = 1
    vm.dirty_ratio = 40
    vm.dirty_background_ratio = 10
    vm.overcommit_memory = 2
    vm.overcommit_ratio = 80
    
    # File system tuning
    fs.aio-max-nr = 3145728
    fs.file-max = 6815744
    EOF
  # Apply sysctl but ignore missing parameters (some may not exist on all kernel versions)
  - sysctl -p || true
  
  # Disable transparent huge pages (THP) for OceanBase
  - |
    if test -f /sys/kernel/mm/transparent_hugepage/enabled; then
      echo never > /sys/kernel/mm/transparent_hugepage/enabled
    fi
    if test -f /sys/kernel/mm/transparent_hugepage/defrag; then
      echo never > /sys/kernel/mm/transparent_hugepage/defrag
    fi
  
  # Disable NUMA balancing for better performance
  - |
    if test -f /proc/sys/kernel/numa_balancing; then
      echo 0 > /proc/sys/kernel/numa_balancing
    fi
  
  # Log cloud-init completion
  - echo "Cloud-init bootstrap completed at $(date)" > /var/log/oceanbase-bootstrap-complete.log

  # Upgrade Rocky Linux to latest 9.x before handing over to Ansible
  - dnf -y upgrade --refresh
  - dnf clean all || true

power_state:
  delay: now
  mode: reboot
  message: "Rebooting after Rocky Linux system update and OceanBase preparation"
  timeout: 60
  condition: true
