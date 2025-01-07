#!/bin/bash
#
# RemoveNodeHost.sh
#
# This script removes *this* Proxmox node from a cluster, assuming the cluster
# no longer trusts or recognizes this node. It cleans up local Corosync/PMXCFS
# files so the node reverts to standalone mode.
#
# Usage:
#   sudo ./RemoveNodeHost.sh
#
# Steps:
#   1) Stop cluster services (corosync, pve-cluster).
#   2) Remove local Corosync configs (/etc/pve/corosync.conf, /etc/corosync/).
#   3) Remove /etc/pve/nodes/<this_node_name> local references.
#   4) Start pve-cluster again (standalone).
#
# Afterwards, you can re-add this node to a new or existing cluster with:
#   pvecm add <IP-of-other-cluster-node>
#
# CAUTION: This is destructive—your node will no longer be part of any cluster.

set -e

# -----------------------------------------------------------------------------
# @function find_utilities_script
# @description
#   Finds the root directory of the scripts folder by traversing upward until
#   it finds a folder containing a Utilities subfolder.
#   Returns the full path to Utilities/Utilities.sh if found, or exits with an
#   error if not found within 15 levels.
# -----------------------------------------------------------------------------
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
  exit 1
}

###############################################################################
# LOCATE AND SOURCE UTILITIES
###############################################################################
UTILITIES_DIR="$(find_utilities_script)"
# shellcheck source=/dev/null
source "${UTILITIES_DIR}/Utilities.sh"

###############################################################################
# MAIN
###############################################################################
main() {

  echo "=== Self Removal from Proxmox Cluster ==="
  echo "This will remove local cluster configs and revert this node to standalone mode."
  echo "It assumes the cluster already 'untrusted' or removed this node externally."
  echo

  # 1. Basic checks
  check_proxmox_and_root  # Must be root and on a Proxmox node

  # 2. Determine local node name
  #    pvecm nodename might fail if membership is broken, so fall back to short hostname
  NODE_NAME="$(pvecm nodename 2>/dev/null || hostname --short)"
  if [[ -z "$NODE_NAME" ]]; then
    echo "Error: Could not determine local node name."
    exit 3
  fi

  echo "Detected local node name: $NODE_NAME"
  echo "Are you sure you want to remove this node from any cluster configs? (y/N)"
  read -r CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi

  # 3. Warn if pve-cluster is not active (we'll proceed anyway)
  if ! systemctl list-units --type=service | grep -q pve-cluster; then
    echo "Warning: 'pve-cluster' service not found or not active. Proceeding anyway..."
  fi

  echo "Stopping cluster services (corosync, pve-cluster)..."
  systemctl stop corosync || true
  systemctl stop pve-cluster || true

  echo "Removing Corosync config files..."
  rm -f /etc/pve/corosync.conf 2>/dev/null || true
  rm -rf /etc/corosync/ 2>/dev/null || true

  if [[ -d "/etc/pve/nodes/$NODE_NAME" ]]; then
    echo "Removing /etc/pve/nodes/$NODE_NAME ..."
    rm -rf "/etc/pve/nodes/$NODE_NAME"
  fi

  echo "Restarting pve-cluster in standalone mode..."
  systemctl start pve-cluster || true

  echo "Ensuring corosync is not running..."
  systemctl stop corosync || true

  echo
  echo "=== Done ==="
  echo "Node '$NODE_NAME' is no longer in any cluster and runs standalone."
  echo "You can verify by running:  pvecm status"
  echo
  echo "If you wish to join an existing cluster, run on this node:"
  echo "  pvecm add <IP-of-other-cluster-node>"
  echo

}

main
