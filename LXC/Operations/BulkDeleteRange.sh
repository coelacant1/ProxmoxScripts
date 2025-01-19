#!/bin/bash
#
# BulkDeleteRange.sh
#
# This script deletes a range of LXC containers by ID, stopping them first if needed,
# then destroying them.
#
# Usage:
#   ./BulkDeleteRange.sh <START_ID> <END_ID>
#
# Example:
#   ./BulkDeleteRange.sh 200 204
#   This will delete CTs 200, 201, 202, 203, 204
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Environment Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Input Validation
###############################################################################
if [ "$#" -ne 2 ]; then
  echo "Usage: ./BulkDeleteRange.sh <START_ID> <END_ID>"
  exit 1
fi

START_ID="$1"
END_ID="$2"

if [ "$START_ID" -gt "$END_ID" ]; then
  echo "Error: START_ID (\"$START_ID\") is greater than END_ID (\"$END_ID\")."
  exit 1
fi

###############################################################################
# Main
###############################################################################
echo "=== Deleting containers from ID \"$START_ID\" to \"$END_ID\" ==="
for (( currentId=START_ID; currentId<=END_ID; currentId++ )); do
  if pct config "$currentId" &>/dev/null; then
    echo "Stopping CT \"$currentId\"..."
    pct stop "$currentId" &>/dev/null

    echo "Destroying CT \"$currentId\"..."
    pct destroy "$currentId" &>/dev/null

    if [ $? -eq 0 ]; then
      echo " - Successfully deleted CT \"$currentId\""
    else
      echo " - Failed to delete CT \"$currentId\""
    fi
  else
    echo " - CT \"$currentId\" does not exist, skipping."
  fi
done

echo "=== Bulk deletion complete. ==="
