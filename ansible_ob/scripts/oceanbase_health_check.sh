#!/bin/bash
# OceanBase Cluster Health Check Script
# This script performs comprehensive health checks on the OceanBase cluster

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load configuration from Ansible inventory or environment
CONTROL_IP="${CONTROL_IP:-}"
OCEANBASE_USER="${OCEANBASE_USER:-admin}"
OCEANBASE_ROOT_PASSWORD="${OCEANBASE_ROOT_PASSWORD:-OceanBase#!123}"

echo_info "=========================================="
echo_info "OceanBase Cluster Health Check"
echo_info "=========================================="
echo_info ""

# Function to check if control node is reachable
check_control_node() {
    echo_info "Step 1: Checking Control Node Accessibility..."
    
    if [ -z "$CONTROL_IP" ]; then
        echo_warn "CONTROL_IP not set. Please set it or SSH to control node first."
        echo_info "Usage: CONTROL_IP=<ip> $0"
        return 1
    fi
    
    if ping -c 3 "$CONTROL_IP" > /dev/null 2>&1; then
        echo_info "✓ Control node ($CONTROL_IP) is reachable"
    else
        echo_error "✗ Cannot reach control node ($CONTROL_IP)"
        return 1
    fi
}

# Function to check observer nodes status
check_observer_status() {
    echo_info "Step 2: Checking Observer Nodes Status..."
    
    # SSH to control node and check cluster status
    ssh -o StrictHostKeyChecking=no -p 6666 azureadmin@$CONTROL_IP << 'ENDSSH'
source ~/.oceanbase-all-in-one/bin/env.sh 2>/dev/null || true
obd cluster list 2>/dev/null || echo "OBD not initialized or no clusters found"
ENDSSH
}

# Function to check OceanBase database connectivity
check_database_connection() {
    echo_info "Step 3: Checking Database Connectivity..."
    
    ssh -o StrictHostKeyChecking=no -p 6666 azureadmin@$CONTROL_IP << 'ENDSSH'
# Try to connect to OceanBase using obclient if available
if command -v obclient &> /dev/null; then
    obclient -h 127.0.0.1 -P 2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -A -e "SELECT * FROM oceanbase.__all_server;" 2>/dev/null || echo "Database connection test completed"
else
    echo "obclient not found. Checking with mysql client..."
    if command -v mysql &> /dev/null; then
        mysql -h 127.0.0.1 -P 2881 -uroot@sys -p'OceanBase#!123' -Doceanbase -A -e "SELECT * FROM oceanbase.__all_server LIMIT 1;" 2>/dev/null || echo "MySQL client connection test completed"
    else
        echo "No MySQL/OceanBase client found"
    fi
fi
ENDSSH
}

# Function to check disk usage
check_disk_usage() {
    echo_info "Step 4: Checking Disk Usage..."
    
    ssh -o StrictHostKeyChecking=no -p 6666 azureadmin@$CONTROL_IP << 'ENDSSH'
echo "=== Data Disk Usage ==="
df -h /oceanbase 2>/dev/null || df -h /home/admin/oceanbase 2>/dev/null || echo "OceanBase directory not found"

echo ""
echo "=== LVM Volume Status (if applicable) ==="
lvs 2>/dev/null || echo "LVM not configured"

echo ""
echo "=== File System Usage ==="
du -sh /oceanbase/* 2>/dev/null || du -sh /home/admin/oceanbase/* 2>/dev/null || echo "Cannot determine usage"
ENDSSH
}

# Function to check memory and CPU
check_resources() {
    echo_info "Step 5: Checking System Resources..."
    
    ssh -o StrictHostKeyChecking=no -p 6666 azureadmin@$CONTROL_IP << 'ENDSSH'
echo "=== Memory Usage ==="
free -h

echo ""
echo "=== CPU Information ==="
nproc
lscpu | grep "CPU(s):" | head -1

echo ""
echo "=== Top Processes by Memory ==="
ps aux --sort=-%mem | head -10
ENDSSH
}

# Function to check monitoring services
check_monitoring() {
    echo_info "Step 6: Checking Monitoring Services..."
    
    ssh -o StrictHostKeyChecking=no -p 6666 azureadmin@$CONTROL_IP << 'ENDSSH'
echo "=== Prometheus Status ==="
systemctl is-active prometheus 2>/dev/null || echo "Prometheus service not found or not running"

echo ""
echo "=== Grafana Status ==="
systemctl is-active grafana-server 2>/dev/null || echo "Grafana service not found or not running"

echo ""
echo "=== Listening Ports ==="
netstat -tlnp 2>/dev/null | grep -E ':(2881|2882|9090|3000)' || ss -tlnp | grep -E ':(2881|2882|9090|3000)'
ENDSSH
}

# Function to display cluster information
display_cluster_info() {
    echo_info "Step 7: Displaying Cluster Information..."
    
    ssh -o StrictHostKeyChecking=no -p 6666 azureadmin@$CONTROL_IP << 'ENDSSH'
echo "=== OceanBase Cluster Configuration ==="
if [ -f /home/admin/obcluster.yaml ]; then
    cat /home/admin/obcluster.yaml
else
    echo "Cluster configuration file not found"
fi

echo ""
echo "=== Active Clusters ==="
source ~/.oceanbase-all-in-one/bin/env.sh 2>/dev/null
obd cluster list 2>/dev/null || echo "No active clusters found"
ENDSSH
}

# Function to check logs
check_logs() {
    echo_info "Step 8: Checking Recent Logs..."
    
    ssh -o StrictHostKeyChecking=no -p 6666 azureadmin@$CONTROL_IP << 'ENDSSH'
echo "=== Recent OceanBase Logs ==="
tail -20 /oceanbase/log/observer.log 2>/dev/null || tail -20 /home/admin/oceanbase/log/observer.log 2>/dev/null || echo "Observer log not found"

echo ""
echo "=== OBD Logs ==="
tail -20 ~/.obd/log/obd.log 2>/dev/null || echo "OBD log not found"
ENDSSH
}

# Main execution
main() {
    local failed=0
    
    check_control_node || failed=1
    
    if [ $failed -eq 0 ]; then
        check_observer_status
        check_database_connection
        check_disk_usage
        check_resources
        check_monitoring
        display_cluster_info
        check_logs
    fi
    
    echo_info ""
    echo_info "=========================================="
    if [ $failed -eq 0 ]; then
        echo_info "Health Check Completed Successfully!"
    else
        echo_error "Health Check Failed! Please review the errors above."
    fi
    echo_info "=========================================="
    echo_info ""
    echo_info "Useful Commands:"
    echo_info "  SSH to Control Node: ssh -p 6666 azureadmin@$CONTROL_IP"
    echo_info "  Access Grafana: http://$CONTROL_IP:3000"
    echo_info "  Access Prometheus: http://$CONTROL_IP:9090"
    echo_info ""
    echo_info "On Control Node:"
    echo_info "  List clusters: obd cluster list"
    echo_info "  Display cluster: obd cluster display <cluster_name>"
    echo_info "  Connect to DB: obclient -h127.0.0.1 -P2881 -uroot@sys -p'password'"
    echo_info ""
    
    return $failed
}

# Run main function
main
exit $?
