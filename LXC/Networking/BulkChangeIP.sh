#!/bin/bash
#
# BulkChangeLXCIPs.sh
#
# This script automates changing the IP addresses of a series of existing LXC containers on Proxmox VE.
# It increments through a specified number of containers, starting from a given container ID, and
# assigns sequential IP addresses based on a starting IP/CIDR. An optional gateway can also be set.
#
# Usage:
#   ./BulkChangeLXCIPs.sh <start_ct_id> <num_cts> <start_ip/cidr> <bridge> [gateway]
#
# Arguments:
#   start_ct_id    - The ID of the first container to update (e.g., 400).
#   num_cts        - How many containers to update (e.g., 5).
#   start_ip/cidr  - The new IP address and subnet mask for the first container (e.g., 192.168.1.50/24).
#   bridge         - The bridge to be used (e.g., vmbr0).
#   gateway        - Optional. The gateway for the IP configuration. If not provided, none is set.
#
# Example:
#   ./BulkChangeLXCIPs.sh 400 5 192.168.1.50/24 vmbr0 192.168.1.1
#   This will update containers 400..404 with IPs 192.168.1.50..54/24, using vmbr0 and gateway 192.168.1.1
#
#   ./BulkChangeLXCIPs.sh 400 5 192.168.1.50/24 vmbr0
#   Same as above, but does not set a gateway.
#
# Notes:
#   - Must be run as root on a Proxmox node.
#   - 'pct' is required (part of the PVE/LXC utilities).
#   - IP increment logic uses Utilities.sh (ip_to_int, int_to_ip) for consistency.

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
  # --- Parse and validate arguments ------------------------------------------
  if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <start_ct_id> <num_cts> <start_ip/cidr> <bridge> [gateway]"
    echo "Example:"
    echo "  $0 400 5 192.168.1.50/24 vmbr0 192.168.1.1"
    echo "  (Updates CTs 400..404 with IPs 192.168.1.50..54/24 on vmbr0, gateway 192.168.1.1)"
    exit 1
  fi

  local start_ct_id="$1"
  local num_cts="$2"
  local start_ip_cidr="$3"
  local bridge="$4"
  local gateway="${5:-}"

  # --- Ensure we are running on Proxmox as root ------------------------------
  check_proxmox_and_root  # Must be root and on a Proxmox node

  # If cluster membership check is needed, uncomment:
  # check_cluster_membership


  # --- Parse out IP and subnet mask ------------------------------------------
  local start_ip
  local subnet_mask
  IFS='/' read -r start_ip subnet_mask <<< "$start_ip_cidr"

  if [[ -z "$start_ip" || -z "$subnet_mask" ]]; then
    echo "Error parsing start_ip/cidr: $start_ip_cidr. Format must be X.X.X.X/XX"
    exit 1
  fi

  # --- Convert start IP to integer -------------------------------------------
  local start_ip_int
  start_ip_int="$(ip_to_int "$start_ip")"

  # --- Display summary -------------------------------------------------------
  echo "=== Starting IP update for $num_cts container(s) ==="
  echo " - Starting container ID: $start_ct_id"
  echo " - Starting IP: $start_ip/$subnet_mask"
  if [[ -n "$gateway" ]]; then
    echo " - Gateway: $gateway"
  else
    echo " - No gateway specified"
  fi

  # --- Main Loop: update IPs for each container ------------------------------
  for (( i=0; i<num_cts; i++ )); do
    local current_ct_id=$(( start_ct_id + i ))
    local current_ip_int=$(( start_ip_int + i ))
    local new_ip
    new_ip="$(int_to_ip "$current_ip_int")"

    if pct config "$current_ct_id" &>/dev/null; then
      echo "Updating IP for container $current_ct_id to $new_ip/$subnet_mask on $bridge..."

      if [[ -z "$gateway" ]]; then
        pct set "$current_ct_id" -net0 name=eth0,bridge="$bridge",ip="$new_ip/$subnet_mask"
      else
        pct set "$current_ct_id" -net0 name=eth0,bridge="$bridge",ip="$new_ip/$subnet_mask",gw="$gateway"
      fi

      if [[ $? -eq 0 ]]; then
        echo " - Successfully updated container $current_ct_id."
      else
        echo " - Failed to update container $current_ct_id (check errors above)."
      fi
    else
      echo " - Container $current_ct_id does not exist. Skipping."
    fi
  done

  echo "=== Bulk IP change process complete! ==="
  echo "If the containers are running, you may need to restart them or reapply networking."
}

# -----------------------------------------------------------------------------
# Run the main function
# -----------------------------------------------------------------------------
main "$@"
