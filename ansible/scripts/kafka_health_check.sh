#!/bin/bash
# kafka_health_check.sh
# Comprehensive Kafka cluster health validation script
# Usage: ./kafka_health_check.sh [--broker-host localhost] [--bootstrap-server localhost:9092]

set -e

BROKER_HOST="${BROKER_HOST:-localhost}"
BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-localhost:9092}"
KAFKA_HOME="${KAFKA_HOME:-/opt/kafka}"
KAFKA_BIN="${KAFKA_HOME}/bin"
SSH_USER="${SSH_USER:-}"
SSH_KEY="${SSH_KEY:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
check_pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; }
check_fail() { echo -e "${RED}❌ FAIL${NC}: $1"; }
check_warn() { echo -e "${YELLOW}⚠️  WARN${NC}: $1"; }

# Execute command locally or remotely via SSH
exec_cmd() {
    local cmd="$1"
    local run_remote="${2:-false}"
    
    if [[ "$run_remote" == "true" && "$BROKER_HOST" != "localhost" ]]; then
        local ssh_target="$BROKER_HOST"
        if [[ -n "$SSH_USER" ]]; then
            ssh_target="$SSH_USER@$BROKER_HOST"
        fi
        
        local ssh_opts=(
            "-o" "BatchMode=yes" 
            "-o" "ConnectTimeout=5" 
            "-o" "StrictHostKeyChecking=accept-new"
            "-o" "UserKnownHostsFile=~/.ssh/known_hosts"
        )
        if [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]]; then
            ssh_opts+=("-i" "$SSH_KEY")
        fi
        
        ssh "${ssh_opts[@]}" "$ssh_target" "$cmd" 2>/dev/null
        return $?
    else
        eval "$cmd" 2>/dev/null
        return $?
    fi

}

echo "==================================================================="
echo "Kafka Cluster Health Check"
echo "==================================================================="
echo "Broker Host: $BROKER_HOST"
echo "Bootstrap Server: $BOOTSTRAP_SERVER"
echo ""

# Auto-detect broker host and bootstrap server when run from management node
# 1) Prefer Prometheus kafka_targets.json (extract first target host, map to 9092)
# 2) Fallback to Ansible inventory/kafka_hosts (extract first IPv4)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROM_SD="/etc/prometheus/file_sd/kafka_targets.json"
INV_FILE="$SCRIPT_DIR/../inventory/kafka_hosts"

if [[ "$BROKER_HOST" == "localhost" && "$BOOTSTRAP_SERVER" == "localhost:9092" ]]; then
    if [[ -r "$PROM_SD" ]]; then
        if command -v jq >/dev/null 2>&1; then
            FIRST_TARGET=$(jq -r '.[0].targets[0]' "$PROM_SD" 2>/dev/null)
            if [[ -n "$FIRST_TARGET" ]]; then
                HOST_ONLY="${FIRST_TARGET%%:*}"
                BROKER_HOST="$HOST_ONLY"
                BOOTSTRAP_SERVER="$HOST_ONLY:9092"
            fi
        else
            # Fallback without jq: pull first host:port with grep/sed
            FIRST_TARGET=$(grep -Eo '"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+"' "$PROM_SD" | head -1 | tr -d '"')
            if [[ -n "$FIRST_TARGET" ]]; then
                HOST_ONLY="${FIRST_TARGET%%:*}"
                BROKER_HOST="$HOST_ONLY"
                BOOTSTRAP_SERVER="$HOST_ONLY:9092"
            fi
        fi
    elif [[ -r "$INV_FILE" ]]; then
        FIRST_IP=$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$INV_FILE" | head -1)
        if [[ -n "$FIRST_IP" ]]; then
            BROKER_HOST="$FIRST_IP"
            BOOTSTRAP_SERVER="$FIRST_IP:9092"
        fi
    fi
fi

echo "Auto-detected Broker Host: $BROKER_HOST"
echo "Auto-detected Bootstrap Server: $BOOTSTRAP_SERVER"
echo ""

# 1. Check Kafka process
echo "[1/8] Checking Kafka broker process..."
if [[ "$BROKER_HOST" == "localhost" ]]; then
    if pgrep -f kafka > /dev/null; then
            BROKER_PID=$(pgrep -f kafka)
            check_pass "Kafka broker process running locally (PID: $BROKER_PID)"
    else
            check_fail "Kafka broker process not running locally"
    fi
else
    SSH_TARGET="$BROKER_HOST"
    if [[ -n "$SSH_USER" ]]; then
        SSH_TARGET="$SSH_USER@$BROKER_HOST"
    fi
    if command -v ssh >/dev/null 2>&1; then
        # Try systemd first, fallback to pgrep. Avoid set -e abort on ssh failure.
        set +e
        SSH_OPTS=(
            "-o" "BatchMode=yes" 
            "-o" "ConnectTimeout=5"
            "-o" "StrictHostKeyChecking=accept-new"
            "-o" "UserKnownHostsFile=~/.ssh/known_hosts"
        )
        if [[ -n "$SSH_KEY" ]]; then
            SSH_OPTS+=("-i" "$SSH_KEY")
        fi
        SSH_ACTIVE=$(ssh ${SSH_OPTS[@]} "$SSH_TARGET" 'systemctl is-active kafka 2>/dev/null || echo unknown' 2>/dev/null || echo "__ssh_failed__")
        set -e
        if [[ "$SSH_ACTIVE" == "active" ]]; then
            check_pass "Kafka broker active on $BROKER_HOST via systemd"
        else
            if ssh ${SSH_OPTS[@]} "$SSH_TARGET" 'pgrep -f kafka >/dev/null' 2>/dev/null; then
                check_pass "Kafka broker process running on $BROKER_HOST"
            else
                if [[ "$SSH_ACTIVE" == "__ssh_failed__" ]]; then
                    check_warn "SSH to $SSH_TARGET failed; set SSH_USER or configure access to verify remote process."
                else
                    check_warn "Unable to verify remote broker process on $BROKER_HOST. Set SSH_USER or run on broker."
                fi
            fi
        fi
    else
        check_warn "ssh command not available; skipping remote broker process check"
    fi
fi

# 2. Check broker port accessibility
echo ""
echo "[2/8] Checking broker port accessibility..."

# Test port using bash built-in socket (timeout + /dev/tcp)
test_port_bash() {
    local host="$1"
    local port="$2"
    local timeout=3
    
    (
        exec 3<>/dev/tcp/"$host"/"$port"
        exec 3>&-
        exec 3<&-
    ) 2>/dev/null
    return $?
}

# Try from control node first using bash built-in
if test_port_bash "$BROKER_HOST" 9092; then
    check_pass "Broker port 9092 is accessible from control node"
elif [[ "$BROKER_HOST" != "localhost" ]] && command -v ssh >/dev/null 2>&1; then
    # Try checking port from the broker itself (localhost) via SSH
    SSH_TARGET="$BROKER_HOST"
    if [[ -n "$SSH_USER" ]]; then
        SSH_TARGET="$SSH_USER@$BROKER_HOST"
    fi
    SSH_OPTS=(
        "-o" "BatchMode=yes" 
        "-o" "ConnectTimeout=5"
        "-o" "StrictHostKeyChecking=accept-new"
        "-o" "UserKnownHostsFile=~/.ssh/known_hosts"
    )
    if [[ -n "$SSH_KEY" ]]; then
        SSH_OPTS+=("-i" "$SSH_KEY")
    fi
    
    # Check if port is listening on the broker itself
    REMOTE_PORT_CHECK=$(ssh ${SSH_OPTS[@]} "$SSH_TARGET" 'ss -tuln 2>/dev/null | grep :9092 || netstat -tuln 2>/dev/null | grep :9092 || true' 2>/dev/null)
    
    if [[ -n "$REMOTE_PORT_CHECK" ]]; then
        check_warn "Port 9092 NOT accessible from control node, but LISTENING on broker $BROKER_HOST (NSG/firewall blocking inbound)"
    else
        check_fail "Broker port 9092 is NOT accessible and NOT listening on broker $BROKER_HOST"
    fi
else
    check_warn "Port 9092 NOT accessible from control node (may need NSG/firewall rules); continuing checks..."
fi

# 3. Check API versions (broker connectivity)
echo ""
echo "[3/8] Checking broker API versions..."
if [ -x "$KAFKA_BIN/kafka-broker-api-versions.sh" ]; then
    API_OUTPUT=$($KAFKA_BIN/kafka-broker-api-versions.sh --bootstrap-server $BOOTSTRAP_SERVER 2>&1)
    API_RC=$?
    if [[ $API_RC -eq 0 ]] && echo "$API_OUTPUT" | head -5 | grep -qE "ApiKey|ApiVersion|API versions|Api Versions"; then
        check_pass "Broker API versions accessible"
        echo "$API_OUTPUT" | head -5
    else
        check_fail "Unable to retrieve API versions (rc=$API_RC): $(echo "$API_OUTPUT" | head -2)"
        exit 1
    fi
else
    # Try remote execution
    if [[ "$BROKER_HOST" != "localhost" ]]; then
        API_OUTPUT=$(exec_cmd "$KAFKA_HOME/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 2>&1" true)
        API_RC=$?
        if [[ $API_RC -eq 0 ]] && echo "$API_OUTPUT" | head -5 | grep -qE "ApiKey|ApiVersion|API versions|Api Versions"; then
            check_pass "Broker API versions accessible (via remote)"
            echo "$API_OUTPUT" | head -5
        else
            check_warn "kafka-broker-api-versions.sh not available or failed (rc=$API_RC). Output: $(echo "$API_OUTPUT" | head -2)"
        fi
    else
        check_warn "kafka-broker-api-versions.sh not found at $KAFKA_BIN (set KAFKA_HOME=/opt/kafka if needed)"
    fi
fi

# 4. Check ZooKeeper connectivity
echo ""
echo "[4/8] Checking ZooKeeper health..."
if [ -x "$KAFKA_BIN/zookeeper-shell.sh" ]; then
    ZK_OUTPUT=$($KAFKA_BIN/zookeeper-shell.sh localhost:2181 ls /brokers/ids 2>&1)
    ZK_RC=$?
    if [[ $ZK_RC -eq 0 ]]; then
        check_pass "ZooKeeper reachable and broker IDs query succeeded"
        echo "$ZK_OUTPUT" | tail -5
    else
        check_warn "ZooKeeper check failed (rc=$ZK_RC): $(echo "$ZK_OUTPUT" | tail -2)"
    fi
else
    if [[ "$BROKER_HOST" != "localhost" ]]; then
        ZK_OUTPUT=$(exec_cmd "$KAFKA_HOME/bin/zookeeper-shell.sh localhost:2181 ls /brokers/ids 2>&1" true)
        if [[ $? -eq 0 ]]; then
            check_pass "ZooKeeper reachable (via remote)"
            echo "$ZK_OUTPUT" | tail -5
        else
            check_warn "zookeeper-shell.sh not available locally or remotely"
        fi
    else
        check_warn "zookeeper-shell.sh not found at $KAFKA_BIN"
    fi
fi

# 5. Check topic configuration
echo ""
echo "[5/8] Checking topics and partitions..."
if [ -x "$KAFKA_BIN/kafka-topics.sh" ]; then
    TOPICS=$($KAFKA_BIN/kafka-topics.sh --bootstrap-server $BOOTSTRAP_SERVER --list 2>&1 | wc -l)
    if [ "$TOPICS" -gt 0 ]; then
        check_pass "Found $TOPICS topics in cluster"
        # Show topic details
        echo ""
        echo "Topic Details:"
        $KAFKA_BIN/kafka-topics.sh --bootstrap-server $BOOTSTRAP_SERVER --describe 2>/dev/null | head -20
    else
        check_pass "No topics configured yet (cluster is clean)"
    fi
else
    # Try remote execution
    if [[ "$BROKER_HOST" != "localhost" ]]; then
        TOPICS_OUTPUT=$(exec_cmd "$KAFKA_HOME/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>&1" true)
        if [[ $? -eq 0 ]]; then
            TOPIC_COUNT=$(echo "$TOPICS_OUTPUT" | wc -l | tr -d ' ')
            if [ "$TOPIC_COUNT" -gt 0 ]; then
                check_pass "Found $TOPIC_COUNT topics in cluster (via remote)"
                echo "$TOPICS_OUTPUT" | head -10
            else
                check_pass "No topics configured yet (cluster is clean)"
            fi
        else
            check_warn "kafka-topics.sh not available locally or remotely"
        fi
    else
        check_warn "kafka-topics.sh not found at $KAFKA_BIN (for topic validation, run on broker or install Kafka tools)"
    fi
fi

# 6. Check broker logs for errors (prefer systemd journal)
echo ""
echo "[6/8] Checking broker logs for errors..."
if [[ "$BROKER_HOST" == "localhost" ]]; then
    if command -v journalctl >/dev/null 2>&1; then
        RECENT=$(journalctl -u kafka -n 200 --no-pager 2>/dev/null)
        if [[ -n "$RECENT" ]]; then
            ERROR_COUNT=$(echo "$RECENT" | grep -E "ERROR|FATAL" | wc -l)
            if [[ "$ERROR_COUNT" -eq 0 ]]; then
                check_pass "No ERROR/FATAL messages in journal"
            else
                check_warn "Found $ERROR_COUNT ERROR/FATAL entries in journal"
                echo "$RECENT" | grep -E "ERROR|FATAL" | tail -5 || true
            fi
        else
            check_warn "No recent journal entries for kafka service"
        fi
    else
        check_warn "journalctl not available; skipping broker log check"
    fi
else
    # Remote journal check via SSH
    SSH_TARGET="$BROKER_HOST"
    if [[ -n "$SSH_USER" ]]; then
        SSH_TARGET="$SSH_USER@$BROKER_HOST"
    fi
    if command -v ssh >/dev/null 2>&1; then
        set +e
        SSH_OPTS=(
            "-o" "BatchMode=yes" 
            "-o" "ConnectTimeout=5"
            "-o" "StrictHostKeyChecking=accept-new"
            "-o" "UserKnownHostsFile=~/.ssh/known_hosts"
        )
        if [[ -n "$SSH_KEY" ]]; then
            SSH_OPTS+=("-i" "$SSH_KEY")
        fi
        REMOTE_RECENT=$(ssh ${SSH_OPTS[@]} "$SSH_TARGET" 'journalctl -u kafka -n 200 --no-pager 2>/dev/null' 2>/dev/null)
        SSH_RC=$?
        set -e
        if [[ $SSH_RC -eq 0 && -n "$REMOTE_RECENT" ]]; then
            ERROR_COUNT=$(echo "$REMOTE_RECENT" | grep -E "ERROR|FATAL" | wc -l)
            if [[ "$ERROR_COUNT" -eq 0 ]]; then
                check_pass "No ERROR/FATAL messages in remote journal on $BROKER_HOST"
            else
                check_warn "Found $ERROR_COUNT ERROR/FATAL entries in remote journal"
                echo "$REMOTE_RECENT" | grep -E "ERROR|FATAL" | tail -5 || true
            fi
        else
            check_warn "Unable to read remote journal on $BROKER_HOST (ensure SSH_USER, SSH_KEY, or run on broker node)"
        fi
    else
        check_warn "ssh command not available; skipping remote broker log check"
    fi
fi

# 7. Check kafka_exporter
echo ""
echo "[7/8] Checking Kafka exporter..."
if pgrep -f kafka_exporter > /dev/null; then
    EXPORTER_PID=$(pgrep -f kafka_exporter)
    check_pass "Kafka exporter process running (PID: $EXPORTER_PID)"
    
    # Check exporter port
    if nc -zv localhost 9308 &> /dev/null; then
        check_pass "Exporter port 9308 is accessible"
        
        # Check metrics endpoint
        if curl -s http://localhost:9308/metrics | grep -q "kafka_"; then
            check_pass "Exporter is serving Kafka metrics"
        else
            check_warn "Exporter metrics endpoint not responding properly"
        fi
    else
        check_fail "Exporter port 9308 is NOT accessible"
    fi
else
        check_warn "Kafka exporter not running on control node (checking remote broker...)"
        # Try remote exporter on broker host (many setups run exporter on each broker)
        if nc -zv "$BROKER_HOST" 9308 &> /dev/null; then
            if curl -s "http://$BROKER_HOST:9308/metrics" | grep -q "kafka_"; then
                check_pass "Remote exporter on $BROKER_HOST:9308 is serving Kafka metrics"
            else
                check_warn "Remote exporter endpoint at $BROKER_HOST:9308 not responding with valid metrics"
            fi
        else
            check_warn "Kafka exporter not accessible locally or at $BROKER_HOST:9308 (may be installed on brokers only)"
        fi
fi

# 8. Check JMX metrics (optional)
echo ""
echo "[8/8] Checking JMX connectivity..."
if [ -n "$KAFKA_JMX_PORT" ]; then
    if nc -zv localhost $KAFKA_JMX_PORT &> /dev/null; then
        check_pass "JMX port $KAFKA_JMX_PORT is accessible"
    else
        check_warn "JMX port $KAFKA_JMX_PORT is not accessible (may be disabled)"
    fi
else
    check_pass "JMX port not configured (not required)"
fi

# Summary
echo ""
echo "==================================================================="
echo "Health Check Summary"
echo "==================================================================="
echo ""
echo "Recommended Validations:"
echo "1. Verify cluster quorum: 3 nodes minimum for resilience"
echo "2. Check ISR (In-Sync Replicas) status: Should match RF"
echo "3. Monitor under load: Watch CPU, Memory, Disk I/O"
echo "4. Test producer/consumer: kafka-console-producer/consumer scripts"
echo "5. Validate Prometheus scraping: Check http://prometheus:9090/targets"
echo ""
echo "For detailed metrics, check Grafana Kafka Cluster dashboard"
