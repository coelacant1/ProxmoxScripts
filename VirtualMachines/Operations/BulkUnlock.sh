#!/bin/bash
#
# BulkUnlock.sh
#
# This script unlocks a range of virtual machines (VMs) within a Proxmox VE environment.
#
# Usage:
#   ./BulkUnlock.sh <first_vm_id> <last_vm_id>
#
# Arguments:
#   first_vm_id - The ID of the first VM to unlock.
#   last_vm_id  - The ID of the last VM to unlock.
#
# Example:
#   # Bulk unlock VMs from ID 400 to 430
#   ./BulkUnlock.sh 400 430
#

source "$UTILITIES"

###############################################################################
# Check prerequisites
###############################################################################
check_root
check_proxmox

###############################################################################
# Main
###############################################################################
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <first_vm_id> <last_vm_id>"
  exit 1
fi

FIRST_VM_ID="$1"
LAST_VM_ID="$2"

for (( vmId=FIRST_VM_ID; vmId<=LAST_VM_ID; vmId++ )); do
  echo "Unlocking VM ID: \"$vmId\""
  qm unlock "$vmId"
done

echo "Bulk unlock operation completed!"
