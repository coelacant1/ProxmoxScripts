#!/bin/bash
#
# BulkStop.sh
#
# This script stops multiple LXC containers using a provided start and end ID.
# It iterates through the range [START_ID ... END_ID] and attempts to stop each one.
#
# Usage:
#   ./BulkStop.sh <START_ID> <END_ID>
#
# Example:
#   ./BulkStop.sh 200 202
#   This will stop containers 200, 201, and 202
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Initialization
###############################################################################
__check_root__
__check_proxmox__

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <START_ID> <END_ID>"
  exit 1
fi

START_ID="$1"
END_ID="$2"

###############################################################################
# Main Logic
###############################################################################
echo "=== Stopping LXC containers in the range [$START_ID ... $END_ID] ==="
for ctId in $(seq "$START_ID" "$END_ID"); do
  if pct config "$ctId" &>/dev/null; then
    echo "Stopping CT \"$ctId\" ..."
    pct stop "$ctId"
    if [ $? -eq 0 ]; then
      echo " - CT \"$ctId\" stopped."
    else
      echo " - Failed to stop CT \"$ctId\"."
    fi
  else
    echo " - CT \"$ctId\" does not exist, skipping."
  fi
done

###############################################################################
# End
###############################################################################
echo "=== Bulk stop process complete. ==="
