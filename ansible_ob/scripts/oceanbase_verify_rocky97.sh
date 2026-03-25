#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEFAULT_INVENTORY_AUTO="$REPO_ROOT/ansible_ob/inventory/oceanbase_hosts_auto"
DEFAULT_INVENTORY="$REPO_ROOT/ansible_ob/inventory/oceanbase_hosts"

INVENTORY="${1:-}"
TARGET_GROUP="${2:-oceanbase}"
TARGET_REGEX='^9\.7([.].*)?$'

if [[ -z "$INVENTORY" ]]; then
  if [[ -f "$DEFAULT_INVENTORY_AUTO" ]]; then
    INVENTORY="$DEFAULT_INVENTORY_AUTO"
  elif [[ -f "$DEFAULT_INVENTORY" ]]; then
    INVENTORY="$DEFAULT_INVENTORY"
  else
    echo "ERROR: No inventory found. Provide one explicitly:"
    echo "  $0 <inventory_path> [group]"
    exit 2
  fi
fi

if ! command -v ansible >/dev/null 2>&1; then
  echo "ERROR: ansible command not found in PATH"
  exit 2
fi

if ! ansible -i "$INVENTORY" "$TARGET_GROUP" --list-hosts >/dev/null 2>&1; then
  echo "ERROR: Unable to resolve group '$TARGET_GROUP' from inventory '$INVENTORY'"
  exit 2
fi

echo "=== Rocky Linux 9.7 Compliance Check ==="
echo "Inventory: $INVENTORY"
echo "Group: $TARGET_GROUP"
echo

ANSIBLE_OUTPUT="$(ansible -i "$INVENTORY" "$TARGET_GROUP" -m shell -a "awk -F= '/^VERSION_ID=/{gsub(/\"/,\"\",\$2); print \$2}' /etc/os-release" -o 2>&1 || true)"

pass_count=0
fail_count=0

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  [[ "$line" =~ ^[[:space:]]*[0-9]+[[:space:]]+hosts ]] && continue

  host="${line%% |*}"

  if [[ "$line" == *"UNREACHABLE!"* ]] || [[ "$line" == *"FAILED!"* ]]; then
    echo "FAIL  $host  UNREACHABLE_OR_FAILED"
    fail_count=$((fail_count + 1))
    continue
  fi

  if [[ "$line" =~ \(stdout\)[[:space:]]+([^[:space:]]+) ]]; then
    version="${BASH_REMATCH[1]}"
    if [[ "$version" =~ $TARGET_REGEX ]]; then
      echo "PASS  $host  VERSION_ID=$version"
      pass_count=$((pass_count + 1))
    else
      echo "FAIL  $host  VERSION_ID=$version"
      fail_count=$((fail_count + 1))
    fi
  else
    echo "FAIL  $host  UNKNOWN_OUTPUT"
    fail_count=$((fail_count + 1))
  fi
done <<< "$ANSIBLE_OUTPUT"

echo
echo "=== Summary ==="
echo "PASS: $pass_count"
echo "FAIL: $fail_count"

if (( fail_count > 0 )); then
  exit 1
fi

exit 0
