#cloud-config
# Cloud-init for OceanBase Standalone VM (Rocky Linux 9)
# Installs OS dependencies and prepares the system before Ansible runs.

package_update: true
package_upgrade: false

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
  - curl
  - wget
  - git
  - nc
  - tar
  - gzip
  - libaio
  - numactl
  - sysstat
  - iotop
  - lsof
  - rsync
  - openssl

runcmd:
  # Ignore Azure SR-IOV NICs that are transparently bonded to synthetic NICs
  - mkdir -p /etc/NetworkManager/conf.d
  - |
    cat > /etc/NetworkManager/conf.d/99-azure-unmanaged-devices.conf <<'EOF'
    [keyfile]
    unmanaged-devices=driver:mana;driver:mlx4_core;driver:mlx5_core
    EOF
  - systemctl restart NetworkManager || true

  # Create the dedicated OceanBase OS user
  - groupadd -f ${ob_admin_username} || true
  - id -u ${ob_admin_username} >/dev/null 2>&1 || useradd -m -g ${ob_admin_username} -s /bin/bash ${ob_admin_username}

  # Create required directory tree and set ownership
  - mkdir -p /oceanbase/data /oceanbase/redo /oceanbase/server /var/log/oceanbase
  - chown -R ${ob_admin_username}:${ob_admin_username} /oceanbase /var/log/oceanbase
  - mkdir -p /home/${ob_admin_username}/.ssh
  - chown -R ${ob_admin_username}:${ob_admin_username} /home/${ob_admin_username}/.ssh
  - chmod 700 /home/${ob_admin_username}/.ssh

  # Disable firewalld (OceanBase manages its own ports via NSG)
  - systemctl disable --now firewalld || true

  # Disable SELinux permanently
  - sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
  - setenforce 0 || true

  # Kernel / system tuning for OceanBase
  - |
    cat >> /etc/sysctl.conf <<'EOF'
    # OceanBase tuning
    fs.aio-max-nr = 1048576
    net.core.somaxconn = 2048
    net.core.rmem_max = 16777216
    net.core.wmem_max = 16777216
    vm.swappiness = 0
    vm.min_free_kbytes = 2097152
    vm.overcommit_memory = 0
    fs.file-max = 6573688
    vm.max_map_count = 655360
    kernel.core_pattern = /oceanbase/data/core-%e-%p-%t
    EOF
  - sysctl -p || true

  # File-descriptor limits
  - |
    cat > /etc/security/limits.d/90-oceanbase.conf <<'EOF'
    ${ob_admin_username} soft nofile 655350
    ${ob_admin_username} hard nofile 655350
    ${ob_admin_username} soft nproc 655360
    ${ob_admin_username} hard nproc 655360
    ${ob_admin_username} soft stack unlimited
    ${ob_admin_username} hard stack unlimited
    root soft nofile 655350
    root hard nofile 655350
    EOF

  # Disable Transparent Huge Pages  
  - |
    cat >> /etc/rc.d/rc.local <<'EOF'
    if test -f /sys/kernel/mm/transparent_hugepage/enabled; then
      echo never > /sys/kernel/mm/transparent_hugepage/enabled
    fi
    if test -f /sys/kernel/mm/transparent_hugepage/defrag; then
      echo never > /sys/kernel/mm/transparent_hugepage/defrag
    fi
    EOF
  - chmod +x /etc/rc.d/rc.local
  - echo never > /sys/kernel/mm/transparent_hugepage/enabled || true
  - echo never > /sys/kernel/mm/transparent_hugepage/defrag  || true

  # Format and mount data disks when they appear (udev rule)
  # Disks arrive as /dev/sdc (LUN 10) and /dev/sdd (LUN 11).
  # Ansible will verify and remount if needed.
  - |
    cat > /usr/local/bin/mount-ob-disks.sh <<'MOUNTEOF'
    #!/bin/bash
    set -e
    mount_disk() {
      local dev="$1" mp="$2" label="$3"
      if [ -b "$dev" ] && ! blkid "$dev" | grep -q ext4; then
        mkfs.ext4 -L "$label" "$dev"
      fi
      mkdir -p "$mp"
      grep -q "$mp" /etc/fstab || echo "LABEL=$label $mp ext4 defaults,nofail 0 2" >> /etc/fstab
      mountpoint -q "$mp" || mount "$mp"
      chown ${ob_admin_username}:${ob_admin_username} "$mp"
    }
    mount_disk /dev/sdc /oceanbase/data ob-data
    mount_disk /dev/sdd /oceanbase/redo ob-redo
    MOUNTEOF
  - chmod +x /usr/local/bin/mount-ob-disks.sh
  - /usr/local/bin/mount-ob-disks.sh || true

final_message: "OceanBase standalone VM cloud-init completed."
