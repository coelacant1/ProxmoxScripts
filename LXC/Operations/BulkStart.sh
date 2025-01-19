#!/bin/bash
#
# BulkStart.sh
#
# This script starts multiple LXC containers in a range defined by a start ID and an end ID.
#
# Usage:
#   ./BulkStart.sh <START_ID> <END_ID>
#
# Example:
#   ./BulkStart.sh 200 202
#   This will start containers 200, 201, and 202
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Setup Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Main
###############################################################################
if [ "$#" -ne 2 ]; then
  echo "Error: You must specify exactly two arguments: <START_ID> <END_ID>."
  echo "Usage: $0 <START_ID> <END_ID>"
  exit 1
fi

startId="$1"
endId="$2"

if [ "$startId" -gt "$endId" ]; then
  echo "Error: START_ID cannot be greater than END_ID."
  exit 1
fi

echo "=== Starting LXC containers from '${startId}' to '${endId}' ==="
for (( ctId=startId; ctId<=endId; ctId++ )); do
  if pct config "${ctId}" &>/dev/null; then
    echo "Starting CT '${ctId}' ..."
    pct start "${ctId}"
    if [ "$?" -eq 0 ]; then
      echo " - CT '${ctId}' started."
    else
      echo " - Failed to start CT '${ctId}'."
    fi
  else
    echo " - CT '${ctId}' does not exist, skipping."
  fi
done

echo "=== Bulk start process complete. ==="
