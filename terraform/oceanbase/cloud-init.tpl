#cloud-config
# Cloud-init configuration for OceanBase observer VMs (Rocky Linux 9.7)
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

  # Create oceanadmin group/user early so mounted directories can be owned correctly
  - groupadd -f ${oceanbase_admin_username} || true
  - id -u ${oceanbase_admin_username} >/dev/null 2>&1 || useradd -m -g ${oceanbase_admin_username} -s /bin/bash ${oceanbase_admin_username} || true
  
  # Create required directories with proper ownership
  - mkdir -p /oceanbase
  - mkdir -p /oceanbase/data
  - mkdir -p /oceanbase/redo
  - mkdir -p /oceanbase/server
  - mkdir -p /var/log/oceanbase
  - mkdir -p /home/${oceanbase_admin_username}/.ssh
  
  # Set up SSH directory permissions
  - chmod 700 /home/${oceanbase_admin_username}/.ssh
  
  # Create oceanbase user/group early (Ansible will reuse)
  - groupadd -f oceanbase || true
  - id -u oceanbase >/dev/null 2>&1 || useradd -r -g oceanbase -s /bin/bash oceanbase || true
  
  # Format and mount OceanBase data and redo disks (supports Azure SCSI and NVMe/PremiumV2)
  - |
    set -euxo pipefail

    find_unmounted_disk_by_target_size() {
      target_size_bytes="$1"
      exclude_dev="$${2:-}"

      mounted_devs=$(lsblk -nrpo NAME,MOUNTPOINT | awk '$2!="" {print $1}')
      mounted_parents=$(for dev in $mounted_devs; do
        parent=$(lsblk -ndo PKNAME "$dev" 2>/dev/null || true)
        if [ -n "$parent" ]; then
          echo "/dev/$parent"
        fi
      done | sort -u)

      best_dev=""
      best_diff=""

      while read -r dev size type; do
        [ "$type" = "disk" ] || continue
        [ "$dev" = "$exclude_dev" ] && continue
        if echo "$mounted_parents" | grep -qx "$dev"; then
          continue
        fi

        diff=$(( size > target_size_bytes ? size - target_size_bytes : target_size_bytes - size ))
        if [ -z "$best_diff" ] || [ "$diff" -lt "$best_diff" ]; then
          best_diff="$diff"
          best_dev="$dev"
        fi
      done <<EOF
$(lsblk -dnbo PATH,SIZE,TYPE)
EOF

      echo "$best_dev"
    }

    ensure_mount() {
      device="$1"
      mount_point="$2"
      owner="$3"

      [ -n "$device" ] || return 1
      mkdir -p "$mount_point"

      if ! blkid "$device" >/dev/null 2>&1; then
        mkfs.xfs -f "$device"
      fi

      if ! mountpoint -q "$mount_point"; then
        mount "$device" "$mount_point"
      fi

      uuid=$(blkid -s UUID -o value "$device")
      if [ -n "$uuid" ] && ! grep -q "$uuid" /etc/fstab; then
        echo "UUID=$uuid $mount_point xfs defaults,nofail 0 2" >> /etc/fstab
      fi

      chmod 755 "$mount_point"
      chown "$owner:$owner" "$mount_point"
    }

    DATA_DISK_DEVICE=""
    REDO_DISK_DEVICE=""

    if [ -e "/dev/disk/azure/data/by-lun/10" ]; then
      DATA_DISK_DEVICE=$(readlink -f /dev/disk/azure/data/by-lun/10)
    fi
    if [ -e "/dev/disk/azure/data/by-lun/11" ]; then
      REDO_DISK_DEVICE=$(readlink -f /dev/disk/azure/data/by-lun/11)
    fi

    if [ -z "$DATA_DISK_DEVICE" ]; then
      DATA_DISK_DEVICE=$(find_unmounted_disk_by_target_size "$(( ${oceanbase_data_disk_size_gb} * 1024 * 1024 * 1024 ))")
    fi
    if [ -z "$REDO_DISK_DEVICE" ]; then
      REDO_DISK_DEVICE=$(find_unmounted_disk_by_target_size "$(( ${oceanbase_redo_disk_size_gb} * 1024 * 1024 * 1024 ))" "$DATA_DISK_DEVICE")
    fi

    echo "Resolved OceanBase cloud-init disks: data=$DATA_DISK_DEVICE redo=$REDO_DISK_DEVICE"

    ensure_mount "$DATA_DISK_DEVICE" /oceanbase/data ${oceanbase_admin_username}
    ensure_mount "$REDO_DISK_DEVICE" /oceanbase/redo ${oceanbase_admin_username}
    chown ${oceanbase_admin_username}:${oceanbase_admin_username} /oceanbase /oceanbase/server || true
  
  # Set up Python environment for Ansible
  - python3 -m venv /home/${oceanbase_admin_username}/ansible-venv || true
  - /home/${oceanbase_admin_username}/ansible-venv/bin/pip install --upgrade pip setuptools
  - /home/${oceanbase_admin_username}/ansible-venv/bin/pip install ansible jinja2 netaddr paramiko
  - chmod -R 755 /home/${oceanbase_admin_username}/ansible-venv
  - chown -R ${oceanbase_admin_username}:${oceanbase_admin_username} /home/${oceanbase_admin_username}/ansible-venv
  
  # Set up file descriptor limits for OceanBase nodes (idempotent)
  - |
    cat > /etc/security/limits.d/99-oceanbase.conf << 'EOF'
    * soft nofile 655360
    * hard nofile 655360
    EOF

  # Configure kernel parameters for OceanBase nodes (idempotent)
  - |
    cat > /etc/sysctl.d/99-oceanbase.conf << 'EOF'
    vm.swappiness = 0
    vm.dirty_ratio = 60
    vm.dirty_background_ratio = 30
    net.core.somaxconn = 65535
    net.ipv4.tcp_max_syn_backlog = 65535
    EOF

  # Apply all sysctl settings from /etc/sysctl.d and /etc/sysctl.conf
  - sysctl --system || true
  
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

  # Upgrade Rocky Linux to the current 9.7 baseline before handing over to Ansible
  - dnf -y upgrade --refresh
  - dnf clean all || true

power_state:
  delay: now
  mode: reboot
  message: "Rebooting after Rocky Linux system update and OceanBase preparation"
  timeout: 60
  condition: true
