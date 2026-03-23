#!/bin/bash
# OceanBase Deployment Helper - Check and Setup SSH Keys
# This script checks for existing SSH keys and helps configure them

set -e

echo "=== Checking SSH Keys on Control Node ==="
echo ""

# Check for existing SSH keys
SSH_DIR="/home/azureadmin/.ssh"
PUB_KEY=""
PRIV_KEY=""

# Look for common key types
for keytype in ed25519 rsa ecdsa; do
    if [ -f "$SSH_DIR/id_$keytype.pub" ]; then
        echo "✓ Found public key: $SSH_DIR/id_$keytype.pub"
        PUB_KEY="$SSH_DIR/id_$keytype.pub"
        PRIV_KEY="$SSH_DIR/id_$keytype"
        break
    fi
done

# If no key found, check authorized_keys
if [ -z "$PUB_KEY" ]; then
    if [ -f "$SSH_DIR/authorized_keys" ]; then
        echo "✓ Found authorized_keys file"
        echo "  You can extract the public key from this file"
        PUB_KEY="$SSH_DIR/authorized_keys"
    else
        echo "✗ No SSH keys found!"
        echo ""
        echo "Generating new ED25519 key pair..."
        ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N "" -C "oceanbase-deployment"
        PUB_KEY="$SSH_DIR/id_ed25519.pub"
        PRIV_KEY="$SSH_DIR/id_ed25519"
    fi
fi

echo ""
echo "Using SSH keys:"
echo "  Public Key:  $PUB_KEY"
echo "  Private Key: $PRIV_KEY"
echo ""

# Update secret.tfvars
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TFVARS="$SCRIPT_DIR/secret.tfvars"

if [ -f "$TFVARS" ]; then
    # Backup original
    cp "$TFVARS" "$TFVARS.backup"
    
    # Update paths
    sed -i "s|^ssh_public_key_path.*|ssh_public_key_path         = \"$PUB_KEY\"|" "$TFVARS"
    sed -i "s|^ssh_private_key_path.*|ssh_private_key_path        = \"$PRIV_KEY\"|" "$TFVARS"
    
    echo "✓ Updated $TFVARS with correct SSH key paths"
    echo ""
    echo "You can now run:"
    echo "  terraform apply -var-file='secret.tfvars'"
else
    echo "✗ secret.tfvars not found at $TFVARS"
    exit 1
fi
