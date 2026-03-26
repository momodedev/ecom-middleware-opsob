#cloud-config
# Cloud-init configuration for CentOS 7.9 OceanBase observer VMs
# Uses yum (not dnf) – CentOS 7 ships with yum, not dnf.

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
  - python3
  - python3-pip
  - jq
  - curl
  - wget
  - git
  - nmap-ncat
  - tar
  - gzip
  - openssl
  - sshpass
  - rsync
  - lsof
  - sysstat
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

  # Update package cache
  - yum makecache || true

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
    set -uxo pipefail

    # Wait up to 5 minutes for data disks to be attached by Terraform
    echo "Waiting for data disks to be attached..."
    disk_wait=0
    while [ $disk_wait -lt 300 ]; do
      if [ -e "/dev/disk/azure/data/by-lun/10" ] && [ -e "/dev/disk/azure/data/by-lun/11" ]; then
        echo "Data disks found after $${disk_wait}s"
        break
      fi
      sleep 10
      disk_wait=$((disk_wait + 10))
      if [ $((disk_wait % 60)) -eq 0 ]; then
        echo "  Still waiting for data disks... ($${disk_wait}s elapsed)"
      fi
    done

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

      lsblk -dnbo PATH,SIZE,TYPE > /tmp/_ci_disks.txt
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
      done < /tmp/_ci_disks.txt
      rm -f /tmp/_ci_disks.txt

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

    if [ -n "$DATA_DISK_DEVICE" ]; then
      ensure_mount "$DATA_DISK_DEVICE" /oceanbase/data ${oceanbase_admin_username} || echo "WARNING: failed to mount data disk"
    else
      echo "WARNING: data disk not found, skipping mount"
    fi
    if [ -n "$REDO_DISK_DEVICE" ]; then
      ensure_mount "$REDO_DISK_DEVICE" /oceanbase/redo ${oceanbase_admin_username} || echo "WARNING: failed to mount redo disk"
    else
      echo "WARNING: redo disk not found, skipping mount"
    fi
    chown ${oceanbase_admin_username}:${oceanbase_admin_username} /oceanbase /oceanbase/server || true

  # Set up Python 3 virtual environment for Ansible
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
  # Apply sysctl but ignore missing parameters
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

  # Log cloud-init bootstrap completion
  - echo "CentOS 7.9 cloud-init bootstrap completed at $(date)" > /var/log/oceanbase-bootstrap-complete.log

# CentOS 7.9 is EOL – no OS upgrade or reboot needed
