#!/bin/bash
#
# This script automates the process of cloning virtual machines (VMs) within a Proxmox VE environment. It clones a source VM into
# a specified number of new VMs, assigning them unique IDs and names based on a user-provided base name. Adding cloned VMs to a
# designated pool is optional. This script is particularly useful for quickly deploying multiple VMs based on a standardized configuration.
#
# Usage:
# ./BulkClone.sh <source_vm_id> <base_vm_name> <start_vm_id> <num_vms> [pool_name]
#
# Arguments:
#   source_vm_id - The ID of the VM that will be cloned.
#   base_vm_name - The base name for the new VMs, which will be appended with a numerical index.
#   start_vm_id - The starting VM ID for the first clone.
#   num_vms - The number of VMs to clone.
#   pool_name - Optional. The name of the pool to which the new VMs will be added. If not provided, VMs are not added to any pool.
#
# Example:
#   ./BulkClone.sh 110 Ubuntu-2C-20GB 400 30 PoolName
#   ./BulkClone.sh 110 Ubuntu-2C-20GB 400 30  # Without specifying a pool

# Check if the minimum required parameters are provided
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <source_vm_id> <base_vm_name> <start_vm_id> <num_vms> [pool_name]"
    exit 1
fi

# Assigning input arguments
SOURCE_VM_ID=$1
BASE_VM_NAME=$2
START_VM_ID=$3
NUM_VMS=$4
POOL_NAME=${5:-}  # Optional pool name, default to an empty string if not provided

# Loop to create clones
for (( i=0; i<$NUM_VMS; i++ )); do
    TARGET_VM_ID=$((START_VM_ID + i))
    NAME_INDEX=$((i + 1))
    VM_NAME="${BASE_VM_NAME}${NAME_INDEX}"

    # Clone the VM and set the constructed name

    # Check if a pool name was provided and add VM to the pool if it was
    if [ -n "$POOL_NAME" ]; then
        qm clone $SOURCE_VM_ID $TARGET_VM_ID --name $VM_NAME --pool $POOL_NAME
    elif 
        qm clone $SOURCE_VM_ID $TARGET_VM_ID --name $VM_NAME
    fi
done

echo "Cloning completed!"
