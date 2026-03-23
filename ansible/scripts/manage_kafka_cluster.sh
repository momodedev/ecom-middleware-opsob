#!/bin/bash
# Unified management script for Kafka cluster lifecycle using Ansible
# Supports: start | stop | reload
# Order:
#   stop   -> stop traffic/monitoring, then Kafka brokers
#   start  -> start Kafka brokers, then monitoring
#   reload -> restart Kafka brokers to apply config changes
#
# Usage examples:
#   ./manage_kafka_cluster.sh stop
#   ./manage_kafka_cluster.sh start --limit kafka-broker-3
#   ./manage_kafka_cluster.sh reload

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INVENTORY_KAFKA="${ANSIBLE_DIR}/inventory/kafka_hosts"
INVENTORY_CTL="${ANSIBLE_DIR}/inventory/inventory.ini"
PLAY_KAFKA_MAINT="${ANSIBLE_DIR}/playbooks/kafka_maintenance.yml"
PLAY_MONITORING="${ANSIBLE_DIR}/playbooks/deploy_monitoring_playbook.yml"

OPERATION=""
LIMIT=""
ANSIBLE_EXTRA=()

usage() {
  cat <<'EOF'
Usage: manage_kafka_cluster.sh <start|stop|reload> [--limit host_pattern]

Operations:
  start   - Start Kafka brokers (ordered) then monitoring stack (Prometheus/Grafana/exporters)
  stop    - Stop monitoring stack first, then gracefully stop Kafka brokers
  reload  - Restart Kafka brokers to apply config changes (no reprovision); monitoring left running

Options:
  --limit <pattern>  Limit hosts (Ansible pattern), e.g. kafka-broker-3 or kafka-broker-[3:5]
EOF
  exit 1
}

[[ $# -lt 1 ]] && usage
OPERATION="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ ! -f "$INVENTORY_KAFKA" ]]; then
  echo "[ERROR] Kafka inventory not found: $INVENTORY_KAFKA" >&2
  exit 1
fi

if [[ ! -f "$PLAY_KAFKA_MAINT" ]]; then
  echo "[ERROR] Playbook missing: $PLAY_KAFKA_MAINT" >&2
  exit 1
fi

case "$OPERATION" in
  stop)
    echo "[INFO] Stopping monitoring stack (Prometheus/Grafana/kafka_exporter) on control node..."
    ansible localhost -i "$INVENTORY_CTL" -m systemd \
      -a 'name=prometheus state=stopped' --become || true
    ansible localhost -i "$INVENTORY_CTL" -m systemd \
      -a 'name=grafana-server state=stopped' --become || true
    ansible localhost -i "$INVENTORY_CTL" -m systemd \
      -a 'name=kafka_exporter state=stopped' --become || true

    echo "[INFO] Gracefully stopping Kafka brokers..."
    export ANSIBLE_HOST_KEY_CHECKING=False
    ansible-playbook -i "$INVENTORY_KAFKA" "$PLAY_KAFKA_MAINT" \
      -e kafka_operation=stop -e operation=stop -e services_logs_dir=/var/log/kafka \
      ${LIMIT:+--limit "$LIMIT"}
    ;;

  start)
    echo "[INFO] Starting Kafka brokers..."
    export ANSIBLE_HOST_KEY_CHECKING=False
    ansible-playbook -i "$INVENTORY_KAFKA" "$PLAY_KAFKA_MAINT" \
      -e kafka_operation=start -e operation=start -e services_logs_dir=/var/log/kafka \
      ${LIMIT:+--limit "$LIMIT"}

    echo "[INFO] Starting monitoring stack (Prometheus/Grafana/exporters)..."
    ansible-playbook -i "$INVENTORY_CTL" "$PLAY_MONITORING" --limit localhost
    ;;

  reload)
    echo "[INFO] Restarting Kafka brokers to apply configuration changes..."
    export ANSIBLE_HOST_KEY_CHECKING=False
    ansible-playbook -i "$INVENTORY_KAFKA" "$PLAY_KAFKA_MAINT" \
      -e kafka_operation=restart -e operation=restart -e services_logs_dir=/var/log/kafka \
      ${LIMIT:+--limit "$LIMIT"}
    ;;

  *) usage ;;
esac

echo "[INFO] Operation '$OPERATION' completed."
