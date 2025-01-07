#!/bin/bash
#
# SetTimeServer.sh
#
# A script to set the timezone across all nodes in a Proxmox VE cluster.
# Defaults to "America/New_York" if no argument is provided.
#
# Usage:
#   ./SetTimeServer.sh <timezone>
#
# Examples:
#   ./SetTimeServer.sh
#   ./SetTimeServer.sh "Europe/Berlin"
#
# This script will:
#   1. Check if running as root on a valid Proxmox node (via check_proxmox_and_root).
#   2. Prompt to install missing utilities such as "ssh" (if not installed).
#   3. Verify the node is part of a cluster (check_cluster_membership).
#   4. Gather remote node IPs using get_remote_node_ips from Utilities.sh.
#   5. Set the specified timezone on each remote node and the local node.
#   6. Prompt whether to keep or remove any newly installed packages.

set -e

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

# Locate and source the Utilities script
UTILITIES_DIR="$(find_utilities_script)"
source "${UTILITIES_DIR}/Utilities.sh"

# Ensure we run as root on a valid Proxmox node
check_proxmox_and_root

# Prompt to install 'ssh' if missing (needed for remote commands)
install_or_prompt "ssh"

# Verify the node is part of a cluster
check_cluster_membership

# Trap to optionally remove installed packages at script exit
trap prompt_keep_installed_packages EXIT

# --- Main ------------------------------------------------------------------

TIMEZONE=${1:-America/New_York}
echo "Selected timezone: $TIMEZONE"

# Retrieve remote node IPs from the cluster
readarray -t REMOTE_NODES < <(get_remote_node_ips)

# Set timezone on each remote node
for NODE_IP in "${REMOTE_NODES[@]}"; do
    echo "Setting timezone to '$TIMEZONE' on node: $NODE_IP"
    if ssh "root@${NODE_IP}" "timedatectl set-timezone \"$TIMEZONE\""; then
        echo " - Timezone set successfully on node: $NODE_IP"
    else
        echo " - Failed to set timezone on node: $NODE_IP"
    fi
done

# Finally, set timezone on the local node
echo "Setting timezone to '$TIMEZONE' on local node..."
if timedatectl set-timezone "$TIMEZONE"; then
    echo " - Timezone set successfully on local node"
else
    echo " - Failed to set timezone on local node"
fi

echo "Timezone setup completed for all nodes!"
