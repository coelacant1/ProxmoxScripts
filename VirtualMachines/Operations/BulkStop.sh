#!/bin/bash
#
# This script stops a range of virtual machines (VMs) within a Proxmox VE environment.
#
# Usage:
# ./BulkStop.sh <first_vm_id> <last_vm_id>
#
# Arguments:
#   first_vm_id - The ID of the first VM to stop.
#   last_vm_id - The ID of the last VM to stop.
#
# Example:
#   ./BulkStop.sh 400 430
#

# Check if the required parameters are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <first_vm_id> <last_vm_id>"
    exit 1
fi

# Assigning input arguments
FIRST_VM_ID=$1
LAST_VM_ID=$2

# Loop to stop VMs in the specified range
for (( vm_id=FIRST_VM_ID; vm_id<=LAST_VM_ID; vm_id++ )); do
    echo "Stopping VM ID: $vm_id"
    qm stop $vm_id
done

echo "Stopping completed!"