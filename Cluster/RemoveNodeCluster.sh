#!/bin/bash
#
# RemoveNodeCluster.sh
#
# Safely remove a node from a Proxmox cluster:
#   - Checks if the node has VMs/LXCs. If yes, refuses removal unless --force is given.
#   - Calls 'pvecm delnode' to remove the node from the cluster membership.
#   - Removes SSH references and /etc/pve/nodes/<node_name> directories from all remaining nodes.
#   - Allows re-adding a node with the same name later without leftover SSH conflicts.
#
# Usage:
#   ./RemoveNodeCluster.sh [--force] <node_name>
#
# Examples:
#   # Normal removal, will refuse if the node has VMs/LXCs:
#   ./RemoveNodeCluster.sh node3
#
#   # Force removal, ignoring the presence of VMs/LXCs:
#   ./RemoveNodeCluster.sh --force node3
#

set -e  # Exit on error

# ---------------------------------------------------------------------------
# @function find_utilities_script
# @description
#   Finds the root directory of the scripts folder by traversing upward until
#   it finds a folder containing a Utilities subfolder.
#   Returns the full path to Utilities/Utilities.sh if found, or exits with an
#   error if not found within 15 levels.
# ---------------------------------------------------------------------------
find_utilities_script() {
  # Check current directory first
  if [[ -d "./Utilities" ]]; then
    echo "./Utilities"
    return 0
  fi

  local rel_path=""
  for _ in {1..15}; do
    cd ..
    # If rel_path is empty, set it to '..' else prepend '../'
    if [[ -z "$rel_path" ]]; then
      rel_path=".."
    else
      rel_path="../$rel_path"
    fi

    if [[ -d "./Utilities" ]]; then
      echo "$rel_path/Utilities"
      return 0
    fi
  done

  echo "Error: Could not find 'Utilities' folder within 15 levels." >&2
  return 1
}

###############################################################################
# Locate and source the Utilities script
###############################################################################
UTILITIES_DIR="$(find_utilities_script)"
source "${UTILITIES_DIR}/Utilities.sh"

###############################################################################
# Preliminary Checks
###############################################################################
check_proxmox_and_root       # Ensure we're root on a valid Proxmox node

# We need 'jq' and 'ssh' for remote checks and node cleanup
install_or_prompt "jq"
install_or_prompt "ssh"

# Also ensure cluster membership is recognized
check_cluster_membership

# At script exit, prompt whether to remove any newly installed packages
trap prompt_keep_installed_packages EXIT

###############################################################################
# Usage Function
###############################################################################
usage() {
  echo "Usage: $0 [--force] <node_name>"
  echo "  --force   Allow removal even if node has VMs/containers."
  exit 1
}

###############################################################################
# Argument Parsing
###############################################################################
FORCE=0
if [[ "$1" == "--force" ]]; then
  FORCE=1
  shift
fi

NODE_NAME="$1"
if [[ -z "$NODE_NAME" ]]; then
  usage
fi

###############################################################################
# Check for VMs or containers on this node (unless --force)
###############################################################################
if [[ "$FORCE" -ne 1 ]]; then
  echo "Checking for VMs/containers on node '$NODE_NAME'..."

  # Query cluster resources for type=vm (includes QEMU + LXC) and filter by node name
  VMS_ON_NODE=$(
    pvesh get /cluster/resources --type vm --output-format json 2>/dev/null \
    | jq -r --arg N "$NODE_NAME" '.[] | select(.node == $N) | "\(.type) \(.vmid)"'
  )

  if [[ -n "$VMS_ON_NODE" ]]; then
    echo "Error: The following VMs/containers still reside on node '$NODE_NAME':"
    echo "$VMS_ON_NODE"
    echo
    echo "Please migrate or remove them first, or re-run with --force to override."
    exit 3
  fi
fi

###############################################################################
# Main Script Logic
###############################################################################
echo "=== Removing node '$NODE_NAME' from the cluster ==="

# 1) Remove node from the Corosync membership
echo "Running: pvecm delnode $NODE_NAME"
if ! pvecm delnode "$NODE_NAME"; then
  echo "Warning: 'pvecm delnode' may fail if the node isn't recognized or is already removed."
  echo "         Continuing with SSH cleanup..."
fi

# 2) Remove /etc/pve/nodes/<node_name> locally if it exists
if [[ -d "/etc/pve/nodes/$NODE_NAME" ]]; then
  echo "Removing local /etc/pve/nodes/$NODE_NAME ..."
  rm -rf "/etc/pve/nodes/$NODE_NAME"
fi

# 3) Gather remaining online nodes to remove SSH references
ONLINE_NODES=$(pvecm nodes | awk '{print $3}')
echo "Cleaning SSH references on other cluster nodes..."
for host in $ONLINE_NODES; do
  # Skip if it's the removed node or blank
  [[ "$host" == "$NODE_NAME" ]] && continue
  [[ -z "$host" ]] && continue

  echo ">>> On node '$host'..."

  # Remove from known_hosts
  ssh "root@${host}" "ssh-keygen -R '${NODE_NAME}' >/dev/null 2>&1 || true"
  ssh "root@${host}" "ssh-keygen -R '${NODE_NAME}.local' >/dev/null 2>&1 || true"

  # Remove from /etc/ssh/ssh_known_hosts if it exists
  ssh "root@${host}" "sed -i '/$NODE_NAME/d' /etc/ssh/ssh_known_hosts 2>/dev/null || true"

  # Remove /etc/pve/nodes/<node_name> if leftover
  ssh "root@${host}" "rm -rf /etc/pve/nodes/$NODE_NAME 2>/dev/null || true"
done

echo
echo "=== Done ==="
echo "Node '$NODE_NAME' has been removed from the cluster."
echo "All known SSH references on remaining cluster nodes have been cleaned."
echo
echo "You may now safely re-add a new server with the same name ('$NODE_NAME') in the future."
