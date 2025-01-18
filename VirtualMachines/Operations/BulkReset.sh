#!/bin/bash
#
# This script resets a range of virtual machines (VMs) within a Proxmox VE environment.
#
# Usage:
# ./BulkReset.sh <first_vm_id> <last_vm_id>
#
# Arguments:
#   first_vm_id - The ID of the first VM to reset.
#   last_vm_id - The ID of the last VM to reset.
#
# Example:
#   ./BulkReset.sh 400 430
#

# Check if the required parameters are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <first_vm_id> <last_vm_id>"
    exit 1
fi

# Assigning input arguments
FIRST_VM_ID=$1
LAST_VM_ID=$2

# Loop to reset VMs in the specified range
for (( vm_id=FIRST_VM_ID; vm_id<=LAST_VM_ID; vm_id++ )); do
    echo "Resetting VM ID: $vm_id"
    qm reset $vm_id
done

echo "Resetting completed!"