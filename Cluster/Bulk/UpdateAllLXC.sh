#!/bin/bash
#
# UpdateAllLXC.sh
#
# A script to apply package updates to all Linux containers (LXC) on every host in a Proxmox cluster.
# Requires root privileges and passwordless SSH between nodes.
#
# Usage:
#   ./UpdateAllLXC.sh
#
# Description:
#   1. Checks root privileges and that this is a Proxmox node (check_proxmox_and_root).
#   2. Verifies that the node is part of a cluster (check_cluster_membership).
#   3. Prompts to install 'ssh' if missing (install_or_prompt "ssh").
#   4. Gathers remote node IPs via get_remote_node_ips (excludes local).
#   5. Determines the local node’s primary IP.
#   6. Iterates over all nodes (local + remote) and enumerates their LXC containers.
#      Uses ssh to run 'pct exec' updates inside each container.
#   7. Prompts whether to keep or remove any packages installed by this script.
#
# Example:
#   ./UpdateAllLXC.sh
#

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
    echo "./Utilities/Utilities.sh"
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
      echo "$rel_path/Utilities/Utilities.sh"
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
# Preliminary Checks via Utilities
###############################################################################
check_proxmox_and_root          # Ensure we are root on a Proxmox node
install_or_prompt "ssh"         # SSH required for remote commands
check_cluster_membership        # Ensure this node is part of a cluster

# Prompt to potentially remove newly installed packages at the end
trap prompt_keep_installed_packages EXIT

###############################################################################
# Gather Nodes
###############################################################################

# Get IP of the local node (first IPv4 address reported by hostname -I)
LOCAL_NODE_IP="$(hostname -I | awk '{print $1}')"
# Gather remote node IPs (excludes local)
readarray -t REMOTE_NODE_IPS < <(get_remote_node_ips)

# Combine local + remote
ALL_NODE_IPS=("$LOCAL_NODE_IP" "${REMOTE_NODE_IPS[@]}")

###############################################################################
# Main Script Logic
###############################################################################
echo "Updating LXC containers on all nodes in the cluster..."

# Iterate over all nodes
for node_ip in "${ALL_NODE_IPS[@]}"; do
  echo "--------------------------------------------------"
  echo "Processing LXC containers on node: $node_ip"
  
  # Obtain container IDs from this node
  # tail -n +2 removes the header line from `pct list`
  # Example line format: VMID       Status     Lock Name
  CONTAINERS="$(ssh "root@${node_ip}" "pct list | tail -n +2 | awk '{print \$1}'" 2>/dev/null)"

  if [[ -z "$CONTAINERS" ]]; then
    echo "  No LXC containers found on $node_ip"
    continue
  fi

  # Update each container
  while read -r ctid; do
    [[ -z "$ctid" ]] && continue
    echo "  Updating container CTID: $ctid on node $node_ip..."
    if ssh "root@${node_ip}" "pct exec $ctid -- apt-get update && apt-get upgrade -y"; then
      echo "    Update complete for CTID: $ctid"
    else
      echo "    Update failed for CTID: $ctid"
    fi
  done <<< "$CONTAINERS"
done

echo "All LXC containers have been updated across the cluster."
