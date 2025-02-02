#!/bin/bash
#
# BulkMoveVolume.sh
#
# This script moves the specified volume (e.g., 'rootfs', 'mp0') for each LXC
# container in a given range to a new storage location using 'pct move-volume'.
#
# Usage:
#   ./BulkMoveVolume.sh <start_id> <end_id> <source_volume> <target_storage>
#
# Arguments:
#   start_id       - The starting LXC ID.
#   end_id         - The ending LXC ID.
#   source_volume    - The volume identifier to move (e.g. 'rootfs', 'mp0').
#   target_storage - The storage name to move the volume onto (e.g. 'local-zfs').
#
# Example:
#   ./BulkMoveVolume.sh 100 105 rootfs local-zfs
#   This will move the 'rootfs' volume of LXCs 100..105 to 'local-zfs'.
#
source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Initial Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Parse Arguments
###############################################################################
if [ $# -lt 4 ]; then
  echo "Error: Insufficient arguments."
  echo "Usage: $0 <start_id> <end_id> <source_volume> <target_storage>"
  exit 1
fi

START_ID="$1"
END_ID="$2"
DISK_ID="$3"
TARGET_STORAGE="$4"

echo "=== Bulk Move Volume for LXC Containers ==="
echo "Range: \"$START_ID\" to \"$END_ID\""
echo "Volume to move: \"$DISK_ID\""
echo "Target storage: \"$TARGET_STORAGE\""
echo

###############################################################################
# Main Logic
###############################################################################
for ctId in $(seq "$START_ID" "$END_ID"); do
  if pct config "$ctId" &>/dev/null; then
    echo "Processing LXC \"$ctId\"..."
    runningState=$(pct status "$ctId" | awk '{print $2}')
    
    if [ "$runningState" == "running" ]; then
      echo " - Container \"$ctId\" is running. Stopping container..."
      pct stop "$ctId"
    fi

    echo " - Moving \"$DISK_ID\" of CT \"$ctId\" to \"$TARGET_STORAGE\"..."
    if pct move-volume "$ctId" "$DISK_ID" "$TARGET_STORAGE"; then
      echo " - Successfully moved \"$DISK_ID\" of CT \"$ctId\" to \"$TARGET_STORAGE\"."
    else
      echo "Error: Failed to move volume for CT \"$ctId\"."
    fi
    echo
  else
    echo "LXC \"$ctId\" does not exist. Skipping."
  fi
done

echo "=== Bulk volume move complete! ==="
