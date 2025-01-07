#!/bin/bash
#
# BulkChangeDNS.sh
#
# This script updates DNS nameservers for a series of LXC containers.
#
# Usage:
#   ./BulkChangeDNS.sh <start_ct_id> <num_cts> <dns1> [<dns2>] ...
#
# Example:
#   ./BulkChangeDNS.sh 400 3 8.8.8.8 1.1.1.1
#   This updates containers 400..402 to use DNS servers 8.8.8.8 and 1.1.1.1
#
# Note:
#   - You can pass more than two DNS servers if desired. They get appended.
#   - If you want to specify a single DNS server, omit the rest.
#   - Must be run as root on a Proxmox node.

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
  # --- Parse arguments -------------------------------------------------------
  if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <start_ct_id> <num_cts> <dns1> [<dns2> <dns3> ...]"
    echo "Example:"
    echo "  $0 400 3 8.8.8.8 1.1.1.1"
    exit 1
  fi

  local start_ct_id="$1"
  local num_cts="$2"

  # Shift away the first two arguments so that remaining args are all DNS servers
  shift 2
  local dns_servers="$*"

  echo "DNS servers to set: $dns_servers"
  echo "=== Starting DNS update for $num_cts container(s), beginning at CT ID $start_ct_id ==="

  # --- Basic checks ----------------------------------------------------------
  check_proxmox_and_root  # Must be root and on a Proxmox node

  # If a cluster check is needed, uncomment the next line:
  # check_cluster_membership

  # --- Main Loop -------------------------------------------------------------
  for (( i=0; i<num_cts; i++ )); do
    local current_ct_id=$(( start_ct_id + i ))

    # Check if container exists
    if pct config "$current_ct_id" &>/dev/null; then
      echo "Updating DNS for container $current_ct_id to: $dns_servers"
      pct set "$current_ct_id" -nameserver "$dns_servers"
      if [[ $? -eq 0 ]]; then
        echo " - Successfully updated DNS for CT $current_ct_id."
      else
        echo " - Failed to update DNS for CT $current_ct_id."
      fi
    else
      echo " - Container $current_ct_id does not exist. Skipping."
    fi
  done

  echo "=== Bulk DNS change process complete! ==="
}

# -----------------------------------------------------------------------------
# Run the main function
# -----------------------------------------------------------------------------
main
