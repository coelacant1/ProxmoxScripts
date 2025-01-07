#!/bin/bash
#
# BulkSetCPU.sh
#
# This script sets the CPU type and core count for a series of LXC containers.
#
# Usage:
#   ./BulkSetCPU.sh <start_ct_id> <num_cts> <cpu_type> <core_count> [sockets]
#
# Example:
#   ./BulkSetCPU.sh 400 3 host 4
#   This sets containers 400..402 to CPU type=host and 4 cores
#
#   ./BulkSetCPU.sh 400 3 host 4 2
#   Sets containers 400..402 to CPU type=host, 4 cores, 2 sockets
#
# Notes:
#   - Must be run as root on a Proxmox node.
#   - 'pct' is required (part of the PVE/LXC utilities).
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
# LOCATE AND SOURCE UTILITIES
###############################################################################
UTILITIES_DIR="$(find_utilities_script)"
# shellcheck source=/dev/null
source "${UTILITIES_DIR}/Utilities.sh"

###############################################################################
# MAIN
###############################################################################
main() {
  # --- Parse arguments -------------------------------------------------------
  if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <start_ct_id> <num_cts> <cpu_type> <core_count> [sockets]"
    echo "Example:"
    echo "  $0 400 3 host 4"
    echo "  (Sets containers 400..402 to CPU type=host, 4 cores)"
    echo "  $0 400 3 host 4 2"
    echo "  (Sets containers 400..402 to CPU type=host, 4 cores, 2 sockets)"
    exit 1
  fi

  local start_ct_id="$1"
  local num_cts="$2"
  local cpu_type="$3"
  local core_count="$4"
  local sockets="${5:-1}"  # Default to 1 socket if not provided

  # --- Basic checks ----------------------------------------------------------
  check_proxmox_and_root  # Must be root and on a Proxmox node

  # If a cluster check is needed, uncomment the next line:
  # check_cluster_membership

  # --- Ensure required commands are installed --------------------------------
  install_or_prompt "pct"

  # --- Display summary -------------------------------------------------------
  echo "=== Starting CPU config update for $num_cts container(s) ==="
  echo " - Starting container ID: $start_ct_id"
  echo " - CPU Type: $cpu_type"
  echo " - Core Count: $core_count"
  echo " - Sockets: $sockets"

  # --- Main Loop -------------------------------------------------------------
  for (( i=0; i<num_cts; i++ )); do
    local current_ct_id=$(( start_ct_id + i ))

    # Check if container exists
    if pct config "$current_ct_id" &>/dev/null; then
      echo "Updating CPU for container $current_ct_id..."
      pct set "$current_ct_id" -cpu "$cpu_type" -cores "$core_count" -sockets "$sockets"
      if [[ $? -eq 0 ]]; then
        echo " - Successfully updated CPU settings for CT $current_ct_id."
      else
        echo " - Failed to update CPU settings for CT $current_ct_id."
      fi
    else
      echo " - Container $current_ct_id does not exist. Skipping."
    fi
  done

  echo "=== Bulk CPU config change process complete! ==="

  # --- Prompt to remove installed packages if any were installed in this session
  prompt_keep_installed_packages
}

# -----------------------------------------------------------------------------
# Run the main function
# -----------------------------------------------------------------------------
main
