#!/bin/bash
#
# BulkSetMemory.sh
#
# This script sets the memory (RAM) and optional swap allocation for a range of LXC containers.
#
# Usage:
#   ./BulkSetMemory.sh <start_ct_id> <end_ct_id> <memory_MB> [swap_MB]
#
# Examples:
#   # Sets containers 400..402 to 2048 MB of RAM, no swap
#   ./BulkSetMemory.sh 400 402 2048
#
#   # Sets containers 400..402 to 2048 MB of RAM and 1024 MB of swap
#   ./BulkSetMemory.sh 400 402 2048 1024
#
# Notes:
#   - Must be run as root on a Proxmox node.
#   - 'pct' is included by default on Proxmox 8.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# MAIN
###############################################################################

# Check argument count
if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <start_ct_id> <end_ct_id> <memory_MB> [swap_MB]"
  echo "Examples:"
  echo "  $0 400 402 2048"
  echo "    (Sets containers 400..402 to 2048 MB of RAM, no swap)"
  echo "  $0 400 402 2048 1024"
  echo "    (Sets containers 400..402 to 2048 MB of RAM and 1024 MB of swap)"
  exit 1
fi

START_CT_ID="$1"
END_CT_ID="$2"
MEMORY_MB="$3"
SWAP_MB="${4:-0}"

__check_root__
__check_proxmox__

echo "=== Starting memory config update for containers from \"$START_CT_ID\" to \"$END_CT_ID\" ==="
echo " - Memory (MB): \"$MEMORY_MB\""
echo " - Swap (MB): \"$SWAP_MB\""

for (( currentCtId="$START_CT_ID"; currentCtId<="$END_CT_ID"; currentCtId++ )); do
  if pct config "$currentCtId" &>/dev/null; then
    echo "Updating memory for container \"$currentCtId\"..."
    pct set "$currentCtId" -memory "$MEMORY_MB" -swap "$SWAP_MB"
    if [[ $? -eq 0 ]]; then
      echo " - Successfully updated memory for CT \"$currentCtId\"."
    else
      echo " - Failed to update memory for CT \"$currentCtId\"."
    fi
  else
    echo " - Container \"$currentCtId\" does not exist. Skipping."
  fi
done

echo "=== Bulk memory config change process complete! ==="
