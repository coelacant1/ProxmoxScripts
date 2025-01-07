#!/bin/bash
#
# CreateCluster.sh
#
# A script to create a new Proxmox cluster on a single host, specifying:
#   1) The cluster name (e.g. "MyCluster")
#   2) The management (Corosync) IP for cluster communication
#
# Usage:
#   ./CreateCluster.sh <clustername> <mon-ip>
#
# Example:
#   ./CreateCluster.sh myCluster 192.168.100.10
#
# After running this script, you can join other Proxmox nodes to the cluster with:
#   pvecm add <mon-ip-of-this-node>
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

# Locate and source the Utilities script
UTILITIES_DIR="$(find_utilities_script)"
source "${UTILITIES_DIR}/Utilities.sh"

# Ensure we run as root on a valid Proxmox node
check_proxmox_and_root

# --- Check for required arguments -------------------------------------------
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <clustername> <mon-ip>"
  exit 1
fi

CLUSTER_NAME="$1"
MON_IP="$2"

# --- Check if this host is already part of a cluster ------------------------
if [[ -f "/etc/pve/.members" ]]; then
  echo "WARNING: This host appears to have a cluster config (/etc/pve/.members)."
  echo "If it's already part of a cluster, creating a new one may cause conflicts."
  echo "Press Ctrl-C to abort, or wait 5 seconds to continue..."
  sleep 5
fi

# --- Create the cluster -----------------------------------------------------
echo "Creating new Proxmox cluster: $CLUSTER_NAME"
echo "Using IP for link0: $MON_IP"

# The --bindnet0_addr option is deprecated; we use --link0 address=<IP> instead
pvecm create "$CLUSTER_NAME" --link0 address="$MON_IP"

# --- Post-create notice -----------------------------------------------------
echo
echo "Cluster '$CLUSTER_NAME' created with link0 address set to $MON_IP."
echo "To verify status:  pvecm status"
echo "To join another node to this cluster (on the other node):"
echo "  pvecm add $MON_IP"
