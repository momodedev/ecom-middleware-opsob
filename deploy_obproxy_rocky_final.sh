#!/usr/bin/env bash
set -euo pipefail

echo "=== Deploy OBProxy to Rocky nodes ==="

NODES=(172.17.1.7 172.17.1.6 172.17.1.5)

for node_ip in "${NODES[@]}"; do
  echo ""
  echo "=== [Node: $node_ip] ==="
  
  # Create service file on remote node using printf to avoid shell interpretation issues
  ssh -o ConnectTimeout=12 -o StrictHostKeyChecking=accept-new oceanadmin@$node_ip 'bash -s' <<'NODEEOF'
set -euo pipefail

# Create service file
sudo tee /etc/systemd/system/obproxy.service > /dev/null <<'SERVICEEOF'
[Unit]
Description=OceanBase OBProxy
After=network.target

[Service]
Type=simple
User=admin
Group=admin
WorkingDirectory=/home/admin
ExecStart=/home/admin/obproxy-4.3.6.1/bin/obproxy -r "172.17.1.7:2881;172.17.1.6:2881;172.17.1.5:2881" -p 2883 -c ob_cluster -o "enable_strict_kernel_release=false,enable_metadb_used=false,enable_cluster_checkout=false"
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICEEOF

echo "[$(date)] Service file created"

# Reload and start
sudo systemctl daemon-reload
echo "[$(date)] Daemon reloaded"

sudo systemctl enable obproxy
echo "[$(date)] OBProxy enabled for auto-start"

sudo systemctl start obproxy
echo "[$(date)] OBProxy service started"

# Wait for startup
sleep 3

# Check status
status=$(systemctl is-active obproxy || echo "inactive")
echo "[$(date)] Service status: $status"

# Check listener
if ss -lntp 2>/dev/null | grep -q ':2883'; then
  echo "[$(date)] Port 2883 listener: ACTIVE"
  ss -lntp | grep ':2883'
else
  echo "[$(date)] Port 2883 listener: NOT FOUND (startup may still be in progress)"
  sleep 2
  ss -lntp 2>/dev/null | grep ':2883' || echo "Still not listening..."
fi

# Check process
if pgrep -f 'obproxy.*2883' > /dev/null; then
  echo "[$(date)] Process obproxy: RUNNING"
else
  echo "[$(date)] Process obproxy: NOT FOUND"
fi

NODEEOF

  echo "--- Completed for $node_ip ---"
done

echo ""
echo "=== Final verification ==="
for node_ip in "${NODES[@]}"; do
  echo ""
  echo "Node: $node_ip"
  ssh -o ConnectTimeout=12 -o StrictHostKeyChecking=accept-new oceanadmin@$node_ip \
    "systemctl is-active obproxy && echo 'Service: ACTIVE' || echo 'Service: INACTIVE'; ss -lntp 2>/dev/null | grep ':2883' && echo 'Listener: PRESENT' || echo 'Listener: NOT FOUND'" 2>&1
done

echo ""
echo "=== Deployment complete ==="
