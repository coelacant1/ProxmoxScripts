#!/bin/bash
#
# BulkResizeStorage.sh
#
# This script resizes a specified disk (typically rootfs) of each LXC container
# in a specified range to a new size (e.g., 20G or +5G).
#
# Usage:
#   ./BulkResizeStorage.sh <start_id> <end_id> <disk_id> <new_size>
#
# Arguments:
#   start_id   - The starting LXC ID
#   end_id     - The ending LXC ID
#   disk_id    - The disk identifier (e.g., 'rootfs' or 'mp0')
#   new_size   - The new size or size increment (e.g., '20G' or '+5G')
#
# Example:
#   # Resizes the rootfs of LXCs 100..105 to 20G each
#   ./BulkResizeStorage.sh 100 105 rootfs 20G
#
#   # Increases the rootfs size of LXCs 100..105 by 5G
#   ./BulkResizeStorage.sh 100 105 rootfs +5G
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Environment Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Usage Check
###############################################################################
if [ $# -lt 4 ]; then
  echo "Error: Missing arguments."
  echo "Usage: $0 <start_id> <end_id> <disk_id> <new_size>"
  exit 1
fi

###############################################################################
# Variable Initialization
###############################################################################
START_ID="$1"
END_ID="$2"
DISK_ID="$3"
NEW_SIZE="$4"

echo "=== Bulk Resize for LXC Containers ==="
echo "Range: \"$START_ID\" to \"$END_ID\""
echo "Disk: \"$DISK_ID\""
echo "New size: \"$NEW_SIZE\""
echo

###############################################################################
# Main Logic
###############################################################################
for ctId in $(seq "$START_ID" "$END_ID"); do
  if pct config "$ctId" &>/dev/null; then
    echo "Resizing \"$DISK_ID\" of LXC \"$ctId\" to \"$NEW_SIZE\"..."
    pct resize "$ctId" "$DISK_ID" "$NEW_SIZE"
    if [ $? -eq 0 ]; then
      echo " - Successfully resized \"$DISK_ID\" of CT \"$ctId\"."
    else
      echo " - Failed to resize disk for CT \"$ctId\"."
    fi
    echo
  else
    echo "LXC \"$ctId\" does not exist. Skipping."
  fi
done

echo "=== Bulk resize complete! ==="
