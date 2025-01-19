#!/bin/bash
#
# BulkStartAtBoot.sh
#
# This script bulk-sets multiple LXC containers to start automatically at boot
# within a Proxmox VE environment. It iterates over a specified range of container
# IDs and enables the onboot parameter for each. This is useful for ensuring that
# a group of containers starts automatically after a system reboot.
#
# Usage:
#   ./BulkStartAtBoot.sh <start_ct_id> <num_cts>
#
# Example:
#   ./BulkStartAtBoot.sh 400 30
#   This command sets containers with IDs from 400 to 429 to start at boot.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Dependencies and environment checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Argument validation
###############################################################################
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <start_ct_id> <num_cts>"
  exit 1
fi

START_CT_ID="$1"
NUM_CTS="$2"

if ! [[ "$START_CT_ID" =~ ^[0-9]+$ ]] || ! [[ "$NUM_CTS" =~ ^[0-9]+$ ]]; then
  echo "Error: start_ct_id and num_cts must be positive integers."
  exit 1
fi

###############################################################################
# Main logic
###############################################################################
for (( i=0; i<NUM_CTS; i++ )); do
  TARGET_CT_ID=$((START_CT_ID + i))
  if pct status "$TARGET_CT_ID" &>/dev/null; then
    echo "Setting onboot=1 for container ID '$TARGET_CT_ID'..."
    pct set "$TARGET_CT_ID" -onboot 1
    if [ $? -eq 0 ]; then
      echo "Successfully set onboot for container ID '$TARGET_CT_ID'."
    else
      echo "Failed to set onboot for container ID '$TARGET_CT_ID'."
    fi
  else
    echo "Container ID '$TARGET_CT_ID' does not exist. Skipping."
  fi
done

echo "Bulk onboot configuration completed!"
