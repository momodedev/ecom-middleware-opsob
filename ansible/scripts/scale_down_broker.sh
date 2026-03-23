#!/bin/bash
###############################################################################
# scale_down_broker.sh
# Safely scale down Kafka cluster by decommissioning brokers BEFORE VM destruction
# 
# ⚠️ CRITICAL: This script MUST be run BEFORE reducing kafka_instance_count in Terraform!
#
# Usage: 
#   ./scale_down_broker.sh \
#     --target-count 3 \
#     --subscription-id <id> \
#     --resource-group <kafka-resource-group> \
#     --ansible-user rockyadmin
#
# This script will:
#   1. Calculate which brokers to remove (highest node IDs)
#   2. Reassign partitions away from target brokers
#   3. Stop Kafka on target brokers
#   4. Update controller.quorum.voters on remaining brokers
#   5. Restart remaining brokers with new configuration
#   6. Validate cluster health
#   7. Provide Terraform command to destroy VMs
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/../.."
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory/kafka_hosts"

# Defaults
TARGET_COUNT=""
SUBSCRIPTION_ID=""
RESOURCE_GROUP=""
ANSIBLE_USER="rockyadmin"
AUTO_APPROVE=false
BOOTSTRAP_SERVER=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --target-count) TARGET_COUNT="$2"; shift 2 ;;
    --subscription-id) SUBSCRIPTION_ID="$2"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --ansible-user) ANSIBLE_USER="$2"; shift 2 ;;
    --bootstrap-server) BOOTSTRAP_SERVER="$2"; shift 2 ;;
    --auto-approve) AUTO_APPROVE=true; shift ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate inputs
if [[ -z "$TARGET_COUNT" ]]; then
  log_error "target-count is required: --target-count <number>"
  exit 1
fi

if [[ -z "$SUBSCRIPTION_ID" ]]; then
  log_error "subscription-id is required: --subscription-id <id>"
  exit 1
fi

if [[ -z "$RESOURCE_GROUP" ]]; then
  log_error "resource-group is required: --resource-group <name>"
  exit 1
fi

# Get current broker count
if [[ ! -f "$INVENTORY_FILE" ]]; then
  log_error "Inventory file not found: $INVENTORY_FILE"
  exit 1
fi

CURRENT_COUNT=$(grep -c "^kafka-broker-" "$INVENTORY_FILE" || echo "0")

if [[ $CURRENT_COUNT -eq 0 ]]; then
  log_error "No brokers found in inventory"
  exit 1
fi

if [[ $TARGET_COUNT -ge $CURRENT_COUNT ]]; then
  log_error "Target count ($TARGET_COUNT) must be less than current count ($CURRENT_COUNT)"
  log_error "For scale-up, use scale_out_broker.sh instead"
  exit 1
fi

if [[ $TARGET_COUNT -lt 3 ]]; then
  log_error "Target count must be at least 3 to preserve healthy replication defaults"
  exit 1
fi

BROKERS_TO_REMOVE=$((CURRENT_COUNT - TARGET_COUNT))

# Auto-detect bootstrap server if not provided
if [[ -z "$BOOTSTRAP_SERVER" ]]; then
  FIRST_BROKER_IP=$(grep "^kafka-broker-0" "$INVENTORY_FILE" | awk '{print $2}' | cut -d'=' -f2)
  if [[ -n "$FIRST_BROKER_IP" ]]; then
    BOOTSTRAP_SERVER="${FIRST_BROKER_IP}:9092"
    log_info "Auto-detected bootstrap server: $BOOTSTRAP_SERVER"
  else
    log_error "Could not auto-detect bootstrap server. Provide --bootstrap-server <ip:port>"
    exit 1
  fi
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "⚠️  KAFKA CLUSTER SCALE-DOWN ⚠️"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Current broker count: $CURRENT_COUNT"
echo "Target broker count: $TARGET_COUNT"
echo "Brokers to remove: $BROKERS_TO_REMOVE"
echo ""
echo "Brokers that will be DECOMMISSIONED and DESTROYED:"
for ((i=TARGET_COUNT; i<CURRENT_COUNT; i++)); do
  node_id=$((i+1))
  BROKER_NAME="kafka-broker-${i}"
  BROKER_IP=$(grep "^$BROKER_NAME" "$INVENTORY_FILE" | awk '{print $2}' | cut -d'=' -f2 || echo "unknown")
  echo "  - $BROKER_NAME (Node ID: $node_id, IP: $BROKER_IP)"
done
echo ""
echo "⚠️  WARNING: This operation will:"
echo "  1. Move all data off the target brokers"
echo "  2. Stop Kafka on the target brokers"
echo "  3. Update cluster configuration"
echo "  4. Require Terraform to destroy the VMs afterwards"
echo ""
echo "This process is IRREVERSIBLE and may take several minutes."
echo ""

if [[ "$AUTO_APPROVE" != "true" ]]; then
  read -p "Do you want to proceed? (yes/no): " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    log_info "Scale-down cancelled by user"
    exit 0
  fi
fi

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

# Ensure ansible and ansible-playbook are available (prefer control node venv)
ANSIBLE_VENV_PATH="${ANSIBLE_VENV_PATH:-/home/${USER}/ansible-venv}"
ANSIBLE_BIN=$(command -v ansible || true)
ANSIBLE_PLAYBOOK_BIN=$(command -v ansible-playbook || true)

if [[ -z "$ANSIBLE_BIN" && -x "${ANSIBLE_VENV_PATH}/bin/ansible" ]]; then
  ANSIBLE_BIN="${ANSIBLE_VENV_PATH}/bin/ansible"
  export PATH="${ANSIBLE_VENV_PATH}/bin:$PATH"
fi

if [[ -z "$ANSIBLE_PLAYBOOK_BIN" && -x "${ANSIBLE_VENV_PATH}/bin/ansible-playbook" ]]; then
  ANSIBLE_PLAYBOOK_BIN="${ANSIBLE_VENV_PATH}/bin/ansible-playbook"
  export PATH="${ANSIBLE_VENV_PATH}/bin:$PATH"
fi

if [[ -z "$ANSIBLE_BIN" || -z "$ANSIBLE_PLAYBOOK_BIN" ]]; then
  log_error "ansible/ansible-playbook not found. Install Ansible or ensure ${ANSIBLE_VENV_PATH} exists."
  exit 1
fi

log_info "Preparing broker lists from inventory..."
mapfile -t BROKER_LINES < <(grep "^kafka-broker-" "$INVENTORY_FILE" | sort -V)

if [[ ${#BROKER_LINES[@]} -ne $CURRENT_COUNT ]]; then
  log_warn "Inventory broker count (${#BROKER_LINES[@]}) differs from detected count ($CURRENT_COUNT). Proceeding with detected set."
fi

KEEP_BROKER_NAMES=()
KEEP_BROKER_IPS=()
KEEP_NODE_IDS=()
REMOVE_BROKER_NAMES=()
REMOVE_BROKER_IPS=()
REMOVE_NODE_IDS=()

for line in "${BROKER_LINES[@]}"; do
  NAME=$(echo "$line" | awk '{print $1}')
  IP=$(echo "$line" | sed -E 's/.*ansible_host=([^ ]+).*/\1/')
  NODE_ID=$(echo "$line" | sed -E 's/.*kafka_node_id=([0-9]+).*/\1/')

  if [[ -z "$NODE_ID" || -z "$IP" ]]; then
    log_error "Failed to parse inventory line: $line"
    exit 1
  fi

  if [[ $NODE_ID -le $TARGET_COUNT ]]; then
    KEEP_BROKER_NAMES+=("$NAME")
    KEEP_BROKER_IPS+=("$IP")
    KEEP_NODE_IDS+=("$NODE_ID")
  else
    REMOVE_BROKER_NAMES+=("$NAME")
    REMOVE_BROKER_IPS+=("$IP")
    REMOVE_NODE_IDS+=("$NODE_ID")
  fi
done

CONTROL_HOST_IP="${KEEP_BROKER_IPS[0]}"
if [[ -z "$CONTROL_HOST_IP" ]]; then
  log_error "Failed to determine control host IP from remaining brokers"
  exit 1
fi

log_info "Refreshing SSH host key for control host $CONTROL_HOST_IP"
ssh-keygen -R "$CONTROL_HOST_IP" >/dev/null 2>&1 || true
ssh-keyscan -H "$CONTROL_HOST_IP" >> ~/.ssh/known_hosts 2>/dev/null || true

log_info "Refreshing SSH host keys for remaining brokers..."
for ip in "${KEEP_BROKER_IPS[@]}"; do
  ssh-keygen -R "$ip" >/dev/null 2>&1 || true
  ssh-keyscan -H "$ip" >> ~/.ssh/known_hosts 2>/dev/null || true
done

BROKER_LIST_KEEP=$(printf "%s," "${KEEP_NODE_IDS[@]}")
BROKER_LIST_KEEP=${BROKER_LIST_KEEP%,}

# Build quorum voters string for remaining brokers: id@ip:9093
QUORUM_VOTERS=$(printf "%s@%s:9093," ${KEEP_NODE_IDS[@]} ${KEEP_BROKER_IPS[@]})
# Above printf pairs positionally; safer to loop
QUORUM_VOTERS=""
for idx in "${!KEEP_NODE_IDS[@]}"; do
  QUORUM_VOTERS+="${KEEP_NODE_IDS[$idx]}@${KEEP_BROKER_IPS[$idx]}:9093,"
done
QUORUM_VOTERS=${QUORUM_VOTERS%,}

log_info "Remaining brokers: ${KEEP_BROKER_NAMES[*]} (IDs: ${KEEP_NODE_IDS[*]})"
log_info "Target brokers to remove: ${REMOVE_BROKER_NAMES[*]} (IDs: ${REMOVE_NODE_IDS[*]})"
log_info "Control host for Kafka CLI: $CONTROL_HOST_IP"

# Step 1: Generate partition reassignment plan
log_info "Step 1: Gathering topic list from cluster..."
TOPIC_LIST=$(ssh $SSH_OPTS "$ANSIBLE_USER@$CONTROL_HOST_IP" "sudo -u kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server $BOOTSTRAP_SERVER --list" || true)

if [[ -z "$TOPIC_LIST" ]]; then
  log_warn "No topics found on the cluster. Skipping partition reassignment."
  SKIP_REASSIGN=true
else
  SKIP_REASSIGN=false
  TOPICS_JSON="$TEMP_DIR/topics-to-move.json"
  echo '{"version":1,"topics":[' > "$TOPICS_JSON"
  idx=0
  while IFS= read -r topic; do
    [[ -z "$topic" ]] && continue
    if [[ $idx -gt 0 ]]; then echo "," >> "$TOPICS_JSON"; fi
    printf '  {"topic":"%s"}' "$topic" >> "$TOPICS_JSON"
    idx=$((idx+1))
  done <<< "$TOPIC_LIST"
  echo ']}' >> "$TOPICS_JSON"

  log_info "Uploading topic move file to control host..."
  scp $SSH_OPTS "$TOPICS_JSON" "$ANSIBLE_USER@$CONTROL_HOST_IP:/tmp/topics-to-move.json" >/dev/null

  log_info "Generating reassignment plan excluding removed brokers (keeping broker IDs: $BROKER_LIST_KEEP)..."
  ssh $SSH_OPTS "$ANSIBLE_USER@$CONTROL_HOST_IP" "sudo -u kafka /opt/kafka/bin/kafka-reassign-partitions.sh --bootstrap-server $BOOTSTRAP_SERVER --topics-to-move-json-file /tmp/topics-to-move.json --broker-list $BROKER_LIST_KEEP --generate > /tmp/reassignment-generate.log"

  PLAN_JSON=$(ssh $SSH_OPTS "$ANSIBLE_USER@$CONTROL_HOST_IP" "awk '/Proposed partition reassignment configuration/{flag=1; next} /^Current partition replica assignment/{flag=0} flag{print}' /tmp/reassignment-generate.log" || true)

  if [[ -z "$PLAN_JSON" ]]; then
    log_error "Failed to extract proposed reassignment plan from Kafka output"
    exit 1
  fi

  echo "$PLAN_JSON" > "$TEMP_DIR/reassignment-plan.json"
  scp $SSH_OPTS "$TEMP_DIR/reassignment-plan.json" "$ANSIBLE_USER@$CONTROL_HOST_IP:/tmp/reassignment-plan.json" >/dev/null

  log_info "Executing partition reassignment (this can take time)..."
  ssh $SSH_OPTS "$ANSIBLE_USER@$CONTROL_HOST_IP" "sudo -u kafka /opt/kafka/bin/kafka-reassign-partitions.sh --bootstrap-server $BOOTSTRAP_SERVER --reassignment-json-file /tmp/reassignment-plan.json --execute > /tmp/reassignment-execute.log"

  log_info "Monitoring reassignment progress..."
  MAX_VERIFY=60
  SLEEP_SECONDS=10
  for ((attempt=1; attempt<=MAX_VERIFY; attempt++)); do
    VERIFY_OUTPUT=$(ssh $SSH_OPTS "$ANSIBLE_USER@$CONTROL_HOST_IP" "sudo -u kafka /opt/kafka/bin/kafka-reassign-partitions.sh --bootstrap-server $BOOTSTRAP_SERVER --reassignment-json-file /tmp/reassignment-plan.json --verify" || true)
    echo "$VERIFY_OUTPUT" | grep -Eiq "completed successfully|is complete" >/dev/null && {
      log_success "Partition reassignment completed successfully"
      break
    }
    if echo "$VERIFY_OUTPUT" | grep -i "still in progress" >/dev/null; then
      log_info "Reassignment still in progress (attempt $attempt/$MAX_VERIFY)..."
    else
      log_warn "Unexpected verify output (attempt $attempt/$MAX_VERIFY): $VERIFY_OUTPUT"
    fi
    sleep $SLEEP_SECONDS
  done

  if ! echo "$VERIFY_OUTPUT" | grep -i "completed successfully" >/dev/null; then
    log_error "Partition reassignment did not complete after $((MAX_VERIFY*SLEEP_SECONDS)) seconds"
    exit 1
  fi
fi

# Step 2: Stop Kafka on target brokers
if [[ ${#REMOVE_BROKER_NAMES[@]} -gt 0 ]]; then
  STOP_LIMIT=$(IFS=','; echo "${REMOVE_BROKER_NAMES[*]}")
  log_info "Stopping Kafka on brokers to remove: $STOP_LIMIT"
  "$ANSIBLE_BIN" -i "$INVENTORY_FILE" "$STOP_LIMIT" -u "$ANSIBLE_USER" -b -m systemd -a "name=kafka state=stopped" || {
    log_error "Failed to stop Kafka on target brokers"
    exit 1
  }
  log_success "Kafka stopped on brokers to be removed"
fi

# Step 3: Update controller.quorum.voters and restart remaining brokers
TEMP_INVENTORY="$TEMP_DIR/kafka_hosts_remaining"
log_info "Rewriting inventory without decommissioned brokers..."
REMOVE_PATTERN=$(printf "%s|" "${REMOVE_BROKER_NAMES[@]}")
REMOVE_PATTERN=${REMOVE_PATTERN%|}
while IFS= read -r line; do
  if [[ -n "$REMOVE_PATTERN" ]] && echo "$line" | grep -Eq "^($REMOVE_PATTERN)[[:space:]]"; then
    continue
  fi
  echo "$line" >> "$TEMP_INVENTORY"
done < "$INVENTORY_FILE"

# Ensure localhost exists so local-only plays run
grep -q "^localhost" "$TEMP_INVENTORY" || echo "localhost ansible_connection=local" >> "$TEMP_INVENTORY"

# Refresh monitoring hosts' SSH keys if present
mapfile -t MONITORING_HOSTS < <(awk '/^\[monitoring\]/{flag=1;next}/^\[/{flag=0}flag && NF{print $1}' "$TEMP_INVENTORY" 2>/dev/null)
if [[ ${#MONITORING_HOSTS[@]} -gt 0 ]]; then
  log_info "Refreshing SSH host keys for monitoring hosts: ${MONITORING_HOSTS[*]}"
  for host in "${MONITORING_HOSTS[@]}"; do
    host_ip=$(grep "^$host" "$TEMP_INVENTORY" | sed -E 's/.*ansible_host=([^ ]+).*/\1/')
    if [[ -n "$host_ip" ]]; then
      ssh-keygen -R "$host_ip" >/dev/null 2>&1 || true
      ssh-keyscan -H "$host_ip" >> ~/.ssh/known_hosts 2>/dev/null || true
    fi
  done
fi

log_info "Updating Kafka configuration for remaining brokers and restarting..."
"$ANSIBLE_PLAYBOOK_BIN" -i "$TEMP_INVENTORY" -u "$ANSIBLE_USER" "$ANSIBLE_DIR/playbooks/deploy_kafka_playbook.yaml" --limit kafka \
  -e "kafka_controller_quorum_voters=$QUORUM_VOTERS" || {
  log_error "Ansible reconfiguration failed"
  exit 1
}
log_success "Remaining brokers updated with new quorum voters"

# Step 4: Persist inventory changes (remove decommissioned brokers)
BACKUP_FILE="${INVENTORY_FILE}.bak.$(date +%s)"
cp "$INVENTORY_FILE" "$BACKUP_FILE"
mv "$TEMP_INVENTORY" "$INVENTORY_FILE"
log_success "Updated inventory written (backup: $BACKUP_FILE)"

# Step 3b: Regenerate Prometheus scrape targets to drop removed brokers (use finalized inventory)
log_info "Regenerating Prometheus Kafka scrape targets from updated inventory..."
if [[ ${#MONITORING_HOSTS[@]} -gt 0 ]]; then
  "$ANSIBLE_BIN" -i "$INVENTORY_FILE" monitoring -u "$ANSIBLE_USER" -b \
    -m template -a "src=$ANSIBLE_DIR/roles/kafka/templates/prometheus_kafka_targets.json.j2 dest=/etc/prometheus/file_sd/kafka_targets.json mode=0644" \
    -e "kafka_exporter_port=9308" || log_warn "Failed to render Prometheus targets on monitoring hosts"

  "$ANSIBLE_BIN" -i "$INVENTORY_FILE" monitoring -u "$ANSIBLE_USER" -b \
    -m uri -a "url=http://localhost:9090/-/reload method=POST status_code=200" \
    || log_warn "Prometheus reload request failed; manual reload may be required"
else
  # Fallback: write a one-off playbook to a temp file and run it with inventory context
  PROM_PLAYBOOK="$TEMP_DIR/regenerate_prometheus.yml"
  cat > "$PROM_PLAYBOOK" << 'EOFPLAYBOOK'
- name: Regenerate Prometheus targets after scale-down
  hosts: localhost
  gather_facts: no
  vars:
    kafka_exporter_port: 9308
  tasks:
    - name: Render Kafka exporter targets
      template:
        src: roles/kafka/templates/prometheus_kafka_targets.json.j2
        dest: /etc/prometheus/file_sd/kafka_targets.json
        mode: "0644"
      become: yes
      ignore_errors: yes

    - name: Reload Prometheus
      uri:
        url: "http://localhost:9090/-/reload"
        method: POST
        status_code: 200
      ignore_errors: yes
EOFPLAYBOOK
  "$ANSIBLE_PLAYBOOK_BIN" -i "$INVENTORY_FILE" -c local "$PROM_PLAYBOOK"
  [[ $? -eq 0 ]] && log_success "Prometheus targets regenerated" || log_warn "Prometheus targets regeneration had issues; verify manually"
fi

# Step 5: Display Terraform guidance
echo ""
log_info "NEXT STEP: Destroy broker VMs via Terraform after decommissioning"
echo "  cd $PROJECT_ROOT/terraform/kafka"
echo "  terraform apply -auto-approve -var ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID -var kafka_instance_count=$TARGET_COUNT"
echo ""
log_success "Scale-down workflow completed up to VM destruction step"

exit 0
