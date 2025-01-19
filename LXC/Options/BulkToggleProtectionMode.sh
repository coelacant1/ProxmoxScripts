#!/bin/bash
#
# BulkToggleProtectionMode.sh
#
# This script bulk enables or disables the protection mode for multiple LXC
# containers within a Proxmox VE environment. Protection mode prevents
# containers from being accidentally deleted or modified. This script is useful
# for managing the protection status of a group of containers efficiently.
#
# Usage:
#   ./BulkToggleProtectionMode.sh <action> <start_ct_id> <num_cts>
#
# Examples:
#   # The following command will enable protection for LXC containers
#   # with IDs from 400 to 429 (30 containers total).
#   ./BulkToggleProtectionMode.sh enable 400 30
#
#   # The following command will disable protection for LXC containers
#   # with IDs from 200 to 209 (10 containers total).
#   ./BulkToggleProtectionMode.sh disable 200 10
#
# Function Index:
#   - set_protection
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Validate Environment and Permissions
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Parse and Validate Arguments
###############################################################################
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <action> <start_ct_id> <num_cts>"
  echo "  action: enable | disable"
  exit 1
fi

ACTION="$1"
START_CT_ID="$2"
NUM_CTS="$3"

if [[ "$ACTION" != "enable" && "$ACTION" != "disable" ]]; then
  echo "Error: action must be either 'enable' or 'disable'."
  exit 1
fi

if ! [[ "$START_CT_ID" =~ ^[0-9]+$ ]] || ! [[ "$NUM_CTS" =~ ^[0-9]+$ ]]; then
  echo "Error: start_ct_id and num_cts must be positive integers."
  exit 1
fi

###############################################################################
# Determine Desired Protection State
###############################################################################
if [ "$ACTION" == "enable" ]; then
  PROTECTION_STATE=1
else
  PROTECTION_STATE=0
fi

###############################################################################
# Define Helper Function
###############################################################################
set_protection() {
  local containerId="$1"
  local protectionState="$2"
  pct set "${containerId}" --protected "${protectionState}"
}

###############################################################################
# Main Loop
###############################################################################
for (( i=0; i<NUM_CTS; i++ )); do
  CURRENT_CT_ID=$((START_CT_ID + i))

  if pct status "${CURRENT_CT_ID}" &> /dev/null; then
    echo "Setting protection to '${ACTION}' for container ID '${CURRENT_CT_ID}'..."
    set_protection "${CURRENT_CT_ID}" "${PROTECTION_STATE}"
    if [ $? -eq 0 ]; then
      echo "Successfully set protection to '${ACTION}' for container ID '${CURRENT_CT_ID}'."
    else
      echo "Failed to set protection for container ID '${CURRENT_CT_ID}'."
    fi
  else
    echo "Container ID '${CURRENT_CT_ID}' does not exist. Skipping."
  fi
done

echo "Bulk protection configuration completed!"
