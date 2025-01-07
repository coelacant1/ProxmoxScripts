#!/bin/bash
#
# CreateHAGroup.sh
#
# This script creates a High Availability (HA) group in the Proxmox VE cluster
# and adds the specified VMs to the group.
#
# Usage:
#   ./CreateHAGroup.sh <group_name> <vm_id_1> [<vm_id_2> ... <vm_id_n>]
#
# Example:
#   ./CreateHAGroup.sh myHAGroup 100 101 102
#
# Notes:
#   - You must be root or run via sudo.
#   - This script assumes you have a working Proxmox VE cluster.
#   - The script uses Utilities.sh for common checks and functions.
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
    # 1. Basic checks
    check_proxmox_and_root        # Must be root and on a Proxmox node
    check_cluster_membership      # Ensure we are in a cluster

    # 2. Argument parsing
    if [[ "$#" -lt 2 ]]; then
        echo "Usage: $0 <group_name> <vm_id_1> [<vm_id_2> ... <vm_id_n>]"
        exit 1
    fi

    local GROUP_NAME="$1"
    shift
    local -a VM_IDS=("$@")

    # 3. Create the HA group
    echo "Creating HA group: '$GROUP_NAME'..."
    if ! pvesh create /cluster/ha/groups --group "$GROUP_NAME" --comment "HA group created by script"; then
        echo "Error: Failed to create HA group: $GROUP_NAME"
        exit 1
    fi
    echo "HA group '$GROUP_NAME' created successfully."

    # 4. Add the specified VMs to the HA group
    for VMID in "${VM_IDS[@]}"; do
        echo "Adding VM ID: $VMID to HA group: $GROUP_NAME..."
        if pvesh create /cluster/ha/resources --sid "vm:${VMID}" --group "$GROUP_NAME"; then
            echo " - VM ID: $VMID added to HA group: $GROUP_NAME."
        else
            echo " - Failed to add VM ID: $VMID to HA group: $GROUP_NAME."
        fi
    done

    echo "=== HA group setup process completed! ==="
}

main
