#!/bin/bash
#
# BulkUnlock.sh
#
# This script unlocks a range of LXC containers (CT) by ID, from a start ID to an end ID.
#
# Usage:
#   ./BulkUnlock.sh <start_ct_id> <end_ct_id>
#
# Examples:
#   # Unlock containers 100 through 105
#   ./BulkUnlock.sh 100 105
#
# Notes:
#   - Must be run as root on a Proxmox node.
#   - 'pct' is required (part of the PVE/LXC utilities).
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# MAIN
###############################################################################
# --- Parse arguments -------------------------------------------------------
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <start_ct_id> <end_ct_id>"
  echo "Example:"
  echo "  $0 100 105"
  echo "  (Unlocks containers 100..105)"
  exit 1
fi

START_CT_ID="$1"
END_CT_ID="$2"

# --- Basic checks ----------------------------------------------------------
__check_root__
__check_proxmox__

# --- Display summary -------------------------------------------------------
echo "=== Starting unlock process for containers from \"$START_CT_ID\" to \"$END_CT_ID\" ==="

# --- Main Loop -------------------------------------------------------------
for (( ctId=START_CT_ID; ctId<=END_CT_ID; ctId++ )); do
  if pct config "$ctId" &>/dev/null; then
    echo "Unlocking container \"$ctId\"..."
    if pct unlock "$ctId"; then
      echo " - Successfully unlocked CT \"$ctId\"."
    else
      echo " - Failed to unlock CT \"$ctId\"."
    fi
  else
    echo " - Container \"$ctId\" does not exist. Skipping."
  fi
done

echo "=== Bulk unlock process complete! ==="

# --- Prompt to remove installed packages if any were installed in this session
__prompt_keep_installed_packages__
