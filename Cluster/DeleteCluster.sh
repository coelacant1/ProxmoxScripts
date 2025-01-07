#!/bin/bash
#
# DeleteCluster.sh
#
# Script to remove a single-node Proxmox cluster configuration,
# returning the node to a standalone setup.
#
# Usage:
#   ./DeleteCluster.sh
#
# Warning:
#   - If this node is part of a multi-node cluster, first remove other nodes
#     from the cluster (pvecm delnode <nodename>) until this is the last node.
#   - This process is DESTRUCTIVE and will remove cluster configuration.

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
# Preliminary Checks
###############################################################################
check_proxmox_and_root              # Ensure we're running as root on a Proxmox node

###############################################################################
# Main Script Logic
###############################################################################
echo "=== Proxmox Cluster Removal (Single-Node) ==="
echo "This will remove Corosync/cluster configuration from this node."
read -r -p "Proceed? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

# 1) Check if node is truly alone in the cluster
# (We assume single-node cluster means only one node is present.)
# Using pvecm nodes, we skip the first 2 lines ("Membership info" + header)
# and count how many lines mention Online/Offline.
NODE_COUNT="$(get_number_of_cluster_nodes)"
if [[ "$NODE_COUNT" -gt 1 ]]; then
  echo "Error: This script is for a single-node cluster only."
  echo "Current cluster shows $NODE_COUNT nodes. Remove other nodes first, then re-run."
  exit 2
fi

echo "Stopping cluster services..."
systemctl stop corosync || true
systemctl stop pve-cluster || true

echo "Removing Corosync config from /etc/pve and /etc/corosync..."
rm -f /etc/pve/corosync.conf 2>/dev/null || true
rm -rf /etc/corosync/* 2>/dev/null || true

# Optionally remove additional cluster-related config (caution!):
# rm -f /etc/pve/cluster.conf 2>/dev/null || true

echo "Restarting pve-cluster (it will now run standalone)..."
systemctl start pve-cluster

echo "Verifying that corosync is not running..."
systemctl stop corosync 2>/dev/null || true
systemctl disable corosync 2>/dev/null || true

echo "=== Done ==="
echo "This node is no longer part of any Proxmox cluster."
echo "You can verify by running 'pvecm status' (it should show no cluster)."
