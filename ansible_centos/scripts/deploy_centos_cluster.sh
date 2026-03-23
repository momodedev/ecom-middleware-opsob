#!/usr/bin/env bash
# End-to-end deploy for CentOS broker lane using ansible_centos wrappers.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <resource-group> <broker-admin-username> [control-node-username]" >&2
  exit 1
fi

RESOURCE_GROUP="$1"
BROKER_USER="$2"
CONTROL_USER="${3:-azureadmin}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KAFKA_VERSION="2.3.1"
KAFKA_SCALA_VERSION="2.12"
KAFKA_CACHE_DIR="$BASE_DIR/cache"
KAFKA_HTTP_PORT="18080"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ERROR: ansible-playbook not found in PATH. Activate ansible-venv first." >&2
  exit 1
fi

bash "$SCRIPT_DIR/generate_inventory_centos.sh" "$RESOURCE_GROUP" "$BROKER_USER" "$CONTROL_USER"

# Refresh SSH host keys for broker IPs because Terraform may recreate VMs.
if [[ -f "$BASE_DIR/inventory/kafka_hosts" ]]; then
  while IFS= read -r host_ip; do
    [[ -z "$host_ip" ]] && continue
    ssh-keygen -R "$host_ip" >/dev/null 2>&1 || true
    ssh-keyscan -H "$host_ip" >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
  done < <(awk '{for (i=1; i<=NF; i++) if ($i ~ /^ansible_host=/) {split($i, a, "="); print a[2]}}' "$BASE_DIR/inventory/kafka_hosts" | sort -u)
fi

mkdir -p "$KAFKA_CACHE_DIR"

KAFKA_SELECTED_VERSION="$KAFKA_VERSION"
KAFKA_ARCHIVE_NAME="kafka_${KAFKA_SCALA_VERSION}-${KAFKA_SELECTED_VERSION}.tgz"
KAFKA_CACHE_PATH="$KAFKA_CACHE_DIR/$KAFKA_ARCHIVE_NAME"

if [[ ! -s "$KAFKA_CACHE_PATH" ]]; then
  echo "[prep] Downloading Kafka archive on control node cache: $KAFKA_ARCHIVE_NAME"

  # ?action=download tells Apache closer.lua to issue a real 302 redirect to an
  # actual mirror binary instead of returning an HTML chooser page.
  download_sources=(
    "${KAFKA_231_URL:-${KAFKA_232_URL:-}}"
    "https://www.apache.org/dyn/closer.lua/kafka/${KAFKA_SELECTED_VERSION}/${KAFKA_ARCHIVE_NAME}?action=download"
    "https://archive.apache.org/dist/kafka/${KAFKA_SELECTED_VERSION}/${KAFKA_ARCHIVE_NAME}"
    "https://downloads.apache.org/kafka/${KAFKA_SELECTED_VERSION}/${KAFKA_ARCHIVE_NAME}"
  )

  for src in "${download_sources[@]}"; do
    [[ -z "$src" ]] && continue
    echo "[prep]   trying: $src"
    tmp_path="${KAFKA_CACHE_PATH}.tmp"
    if command -v curl >/dev/null 2>&1; then
      curl --fail --location --retry 3 --retry-delay 2 \
        --max-time 600 "$src" -o "$tmp_path" 2>/dev/null || { rm -f "$tmp_path"; continue; }
    elif command -v wget >/dev/null 2>&1; then
      wget --tries=3 --timeout=600 -O "$tmp_path" "$src" || { rm -f "$tmp_path"; continue; }
    else
      echo "ERROR: neither curl nor wget is available to pre-download Kafka archive." >&2
      exit 1
    fi
    # Verify the file is a real gzip archive, not an HTML page.
    if file "$tmp_path" 2>/dev/null | grep -qi "gzip\|tar\|compressed"; then
      mv "$tmp_path" "$KAFKA_CACHE_PATH"
      echo "[prep]   downloaded successfully from: $src"
      break
    else
      echo "[prep]   rejected (not a valid archive, got HTML or empty): $src"
      rm -f "$tmp_path"
    fi
  done
fi

if [[ ! -s "$KAFKA_CACHE_PATH" ]]; then
  echo "ERROR: Kafka 2.3.1 archive unavailable from configured sources." >&2
  echo "       Required file: $KAFKA_ARCHIVE_NAME" >&2
  echo "       Place it manually at: $KAFKA_CACHE_PATH" >&2
  echo "       Or set a direct URL: export KAFKA_231_URL='https://<your-repo>/kafka_2.12-2.3.1.tgz'" >&2
  exit 1
fi

echo "[prep] Using Kafka binary version: ${KAFKA_SELECTED_VERSION} (${KAFKA_ARCHIVE_NAME})"

if command -v python3 >/dev/null 2>&1; then
  PY_HTTP_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PY_HTTP_BIN="python"
else
  echo "ERROR: python3/python is required on control node to host local Kafka archive." >&2
  exit 1
fi

CONTROL_PRIVATE_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [[ -z "${CONTROL_PRIVATE_IP:-}" ]]; then
  echo "ERROR: unable to determine control node private IP (hostname -I)." >&2
  exit 1
fi

echo "[prep] Serving Kafka archive locally at http://${CONTROL_PRIVATE_IP}:${KAFKA_HTTP_PORT}/${KAFKA_ARCHIVE_NAME}"
"$PY_HTTP_BIN" -m http.server "$KAFKA_HTTP_PORT" --directory "$KAFKA_CACHE_DIR" >/tmp/kafka_http_server.log 2>&1 &
KAFKA_HTTP_PID=$!
cleanup() {
  if [[ -n "${KAFKA_HTTP_PID:-}" ]] && kill -0 "$KAFKA_HTTP_PID" 2>/dev/null; then
    kill "$KAFKA_HTTP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Fix DNS first (CentOS OpenLogic images sometimes miss working resolvers).
ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "sudo bash -lc 'printf \"nameserver 168.63.129.16\\nnameserver 1.1.1.1\\n\" > /etc/resolv.conf'" \
  || true

# Replace all legacy/mirrorlist repos with CentOS 7.9 vault repos.
ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "sudo bash -lc 'for f in /etc/yum.repos.d/*.repo; do mv \"\$f\" \"\$f.disabled\" || true; done; cat > /etc/yum.repos.d/CentOS-Vault.repo <<\"EOF\"
[base]
name=CentOS-7.9.2009 - Base
baseurl=http://vault.centos.org/7.9.2009/os/\$basearch/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS-7.9.2009 - Updates
baseurl=http://vault.centos.org/7.9.2009/updates/\$basearch/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS-7.9.2009 - Extras
baseurl=http://vault.centos.org/7.9.2009/extras/\$basearch/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF'" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "sudo yum clean all; sudo rm -rf /var/cache/yum; sudo yum makecache -y" \
  || true

# Bootstrap Python and Java using raw (works even when python is initially absent).
ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "test -x /usr/bin/python || (sudo yum -y install python || sudo yum -y install python2 || true)" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "test -x /usr/bin/python3 || (sudo yum -y install python3 || sudo yum -y install python36 || true)" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "rpm -q java-11-openjdk >/dev/null 2>&1 || sudo yum -y install java-11-openjdk java-11-openjdk-devel" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible -i "$BASE_DIR/inventory/kafka_hosts" kafka \
  -m raw \
  -a "test -x /usr/bin/python || test ! -x /usr/bin/python3 || sudo ln -sf /usr/bin/python3 /usr/bin/python" \
  || true

ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "$BASE_DIR/inventory/kafka_hosts" "$BASE_DIR/playbooks/deploy_kafka_playbook.yml" \
  -e "kafka_primary_url=http://${CONTROL_PRIVATE_IP}:${KAFKA_HTTP_PORT}/${KAFKA_ARCHIVE_NAME}" \
  -e "kafka_fallback_url=http://${CONTROL_PRIVATE_IP}:${KAFKA_HTTP_PORT}/${KAFKA_ARCHIVE_NAME}" \
  -e "kafka_version=${KAFKA_SELECTED_VERSION}" \
  -e "kafka_scala_version=${KAFKA_SCALA_VERSION}" \
  -e "kafka_archive_path=/tmp/${KAFKA_ARCHIVE_NAME}" \
  -e "kafka_download_timeout=120" \
  -e "kafka_data_dir=/data/kafka/kafka-logs" \
  -e "kafka_log_dirs=/data/kafka/kafka-logs"
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i "$BASE_DIR/inventory/inventory.ini" "$BASE_DIR/playbooks/deploy_monitoring_playbook.yml"

echo "CentOS Kafka + monitoring deployment completed."
