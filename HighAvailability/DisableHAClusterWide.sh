#!/bin/bash
#
# DisableHAClusterWide.sh
#
# This script disables High Availability (HA) cluster-wide by:
#   1. Removing all HA resources found in the cluster (pvesh /cluster/ha/resources).
#   2. Stopping and disabling the HA services (pve-ha-crm and pve-ha-lrm) on every node.
#
# Usage:
#   ./DisableHAClusterWide.sh
#
# Example:
#   ./DisableHAClusterWide.sh
#
# Notes:
#   - This script expects passwordless SSH or valid root credentials for all nodes.
#   - Once completed, no node in the cluster will run HA services, and no HA resource
#     definitions will remain.
#

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
    # 0. Basic checks
    check_proxmox_and_root        # Must be root and on a Proxmox node
    check_cluster_membership      # Ensure we are in a cluster

    # 1. Ensure required commands are installed
    install_or_prompt "jq"
    install_or_prompt "ssh"

    echo "=== Disabling HA on the entire cluster ==="

    # 2. Retrieve and remove all HA resources from the cluster
    echo "=== Retrieving all HA resources ==="
    ALL_RESOURCES="$(pvesh get /cluster/ha/resources --output-format json | jq -r '.[].sid')"

    if [[ -z "$ALL_RESOURCES" ]]; then
      echo " - No HA resources found in the cluster."
    else
      echo " - The following HA resources will be removed:"
      echo "$ALL_RESOURCES"
      echo

      for RES in $ALL_RESOURCES; do
        echo "Removing HA resource: $RES ..."
        if pvesh delete "/cluster/ha/resources/${RES}"; then
          echo " - Successfully removed: $RES"
        else
          echo " - Failed to remove: $RES"
        fi
        echo
      done
    fi

    # 3. Stop and disable HA services on every node in the cluster using IPs
    echo "=== Disabling HA services (CRM, LRM) on all nodes ==="
    readarray -t REMOTE_NODE_IPS < <(get_remote_node_ips)

    for NODE_IP in "${REMOTE_NODE_IPS[@]}"; do
      echo " - Processing node with IP: $NODE_IP"

      echo "   Stopping pve-ha-crm and pve-ha-lrm..."
      ssh "root@${NODE_IP}" "systemctl stop pve-ha-crm pve-ha-lrm"

      echo "   Disabling pve-ha-crm and pve-ha-lrm on startup..."
      ssh "root@${NODE_IP}" "systemctl disable pve-ha-crm pve-ha-lrm"

      echo "   Done for node: $NODE_IP"
      echo
    done

    echo "=== HA has been disabled on all nodes in the cluster. ==="
    echo "No HA resources remain, and HA services are stopped & disabled cluster-wide."

    # 4. Prompt to remove any packages installed during this session
    prompt_keep_installed_packages
}

# Run the main function
main
