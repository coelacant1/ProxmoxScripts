#!/bin/bash
#
# BulkChangeUserPass.sh
#
# This script changes a specified user’s password in a range of LXC containers.
# It uses 'pct exec' to run 'chpasswd' inside each container.
#
# Usage:
#   ./BulkChangeUserPass.sh <start_ct_id> <end_ct_id> <username> <new_password>
#
# Example:
#   # Updates the root password on CTs 400..402 to 'MyNewPass123'.
#   ./BulkChangeUserPass.sh 400 402 root MyNewPass123
#
# Note:
#   - The container(s) must be running for 'pct exec' to succeed.
#   - Adjust logic if you want to handle containers that are stopped.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Initial Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Argument Parsing
###############################################################################
if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <start_ct_id> <end_ct_id> <username> <new_password>"
  exit 1
fi

START_CT_ID="$1"
END_CT_ID="$2"
USERNAME="$3"
NEW_PASSWORD="$4"

###############################################################################
# Main Logic
###############################################################################
echo "=== Starting password update for containers from \"$START_CT_ID\" through \"$END_CT_ID\" ==="
echo "Target user: \"$USERNAME\""

for (( ctId=START_CT_ID; ctId<=END_CT_ID; ctId++ )); do
  if pct config "$ctId" &>/dev/null; then
    echo "Changing password for container \"$ctId\"..."
    pct exec "$ctId" -- bash -c "echo \"$USERNAME:$NEW_PASSWORD\" | chpasswd"
    if [ "$?" -eq 0 ]; then
      echo " - Successfully changed password on CT \"$ctId\"."
    else
      echo " - Failed to change password on CT \"$ctId\" (container stopped or other error?)."
    fi
  else
    echo " - Container \"$ctId\" does not exist. Skipping."
  fi
done

echo "=== Bulk password change process complete! ==="
