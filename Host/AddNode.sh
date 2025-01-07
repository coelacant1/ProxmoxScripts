#!/bin/bash
#
# AddNode.sh
#
# A script to join a new Proxmox node to an existing cluster using "pvecm add".
# Run **on the NEW node** that you want to add to the cluster.
#
# Usage:
#   ./AddNode.sh <cluster-IP> [<local-node-IP>]
#
# Example:
#   1) If you only have one NIC/IP (cluster IP is 172.20.120.65, local node IP is 172.20.120.66):
#      ./AddNode.sh 172.20.120.65 172.20.120.66
#      This internally runs:
#        pvecm add 172.20.120.65 --link0 172.20.120.66
#
#   2) If you do not specify <local-node-IP>, it will just do:
#      pvecm add 172.20.120.65
#      (No --link0 parameter)
#
# After running this script, you will be prompted for the 'root@pam' password
# of the existing cluster node (the IP you specify). Then Proxmox will transfer
# the necessary keys/config to this node, completing the cluster join.
#
# Note: This script removes any ringX/ringY references and simply uses
#       the '--link0' parameter if you provide a <local-node-IP>.

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
  # --- Ensure we are root -----------------------------------------------------
  check_proxmox_and_root  # Must be root and on a Proxmox node

  # --- Parse Arguments --------------------------------------------------------
  local cluster_ip="$1"
  local local_node_ip="$2"  # optional

  if [[ -z "$cluster_ip" ]]; then
    echo "Usage: $0 <existing-cluster-IP> [<local-node-IP>]"
    exit 1
  fi

  # --- Preliminary Checks -----------------------------------------------------
  # 1) Check if node is already in a cluster
  if [[ -f "/etc/pve/.members" ]]; then
    echo "Detected /etc/pve/.members. This node may already be in a cluster."
    echo "Press Ctrl-C to abort, or wait 5 seconds to continue..."
    sleep 5
  fi

  # --- Build the 'pvecm add' command ------------------------------------------
  local cmd="pvecm add $cluster_ip"
  if [[ -n "$local_node_ip" ]]; then
    cmd+=" --link0 $local_node_ip"
  fi

  # --- Echo summary -----------------------------------------------------------
  echo "=== Join Proxmox Cluster ==="
  echo "Existing cluster IP: $cluster_ip"
  if [[ -n "$local_node_ip" ]]; then
    echo "Using --link0 $local_node_ip"
  fi

  echo
  echo "Running command:"
  echo "  $cmd"
  echo
  echo "You will be prompted for the 'root@pam' password of the EXISTING cluster node ($cluster_ip)."
  echo

  # --- Execute the join -------------------------------------------------------
  eval "$cmd"

  echo
  echo "=== Done ==="
  echo "Check cluster status with:  pvecm status"
  echo "You should see this node listed as part of the cluster."
}

main
