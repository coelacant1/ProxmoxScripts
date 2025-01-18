#!/bin/bash
#
# This script starts a range of virtual machines (VMs) within a Proxmox VE environment.
#
# Usage:
# ./BulkStart.sh <first_vm_id> <last_vm_id>
#
# Arguments:
#   first_vm_id - The ID of the first VM to start.
#   last_vm_id - The ID of the last VM to start.
#
# Example:
#   ./BulkStart.sh 400 430
#

# Check if the required parameters are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <first_vm_id> <last_vm_id>"
    exit 1
fi

# Assigning input arguments
FIRST_VM_ID=$1
LAST_VM_ID=$2

# Loop to start VMs in the specified range
for (( vm_id=FIRST_VM_ID; vm_id<=LAST_VM_ID; vm_id++ )); do
    echo "Starting VM ID: $vm_id"
    qm start $vm_id
done

echo "Starting completed!"