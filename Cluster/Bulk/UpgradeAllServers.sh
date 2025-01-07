#!/bin/bash
#
# UpgradeAllServers.sh
#
# A script to update all servers in the Proxmox cluster.
# Automatically loops through all nodes in the Proxmox cluster, running:
#   apt-get update && apt-get -y upgrade
# on each node (local + remote).
#
# Usage:
#   ./UpgradeAllServers.sh
#
# Description:
#   1. Checks root privileges and confirms this is a Proxmox node.
#   2. Prompts to install 'ssh' if not installed.
#   3. Ensures the node is part of a cluster.
#   4. Gathers remote cluster node IPs using get_remote_node_ips (from Utilities.sh).
#   5. Updates the local node and all remote nodes in the cluster.
#   6. Prompts whether to keep or remove any newly installed packages (like ssh).
#
# Example:
#   ./UpgradeAllServers.sh
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
# Preliminary Checks via Utilities
###############################################################################
check_proxmox_and_root      # Ensure we are root on a Proxmox node
install_or_prompt "ssh"     # SSH is required for remote updates
check_cluster_membership    # Ensure this node is part of a cluster

# Prompt to potentially remove newly installed packages at the end
trap prompt_keep_installed_packages EXIT

###############################################################################
# Gather Node Information
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
echo "Updating all servers in the Proxmox cluster..."

for node_ip in "${ALL_NODE_IPS[@]}"; do
  echo "------------------------------------------------"
  echo "Updating node at IP: $node_ip"

  # If this IP matches our local IP, we update locally
  if [[ "$node_ip" == "$LOCAL_NODE_IP" ]]; then
    apt-get update && apt-get -y upgrade
    echo "Local node update completed."
  else
    # Otherwise, update via SSH
    if ssh "root@${node_ip}" "apt-get update && apt-get -y upgrade"; then
      echo "Remote node $node_ip update completed."
    else
      echo "Failed to update node $node_ip."
    fi
  fi
done

echo "All servers have been successfully updated."
