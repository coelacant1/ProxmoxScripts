#!/bin/bash
#
# This script resizes the storage for a range of virtual machines (VMs) within a Proxmox VE environment.
#
# Usage:
# ./ResizeStorage.sh <start_vm_id> <end_vm_id> <disk> <size>
#
# Arguments:
#   start_vm_id - The ID of the first VM to update.
#   end_vm_id - The ID of the last VM to update.
#   disk - The disk to resize (e.g., 'scsi0', 'virtio0').
#   size - The new size to set for the disk (e.g., '+10G' to add 10GB).
#
# Example:
#   ./ResizeStorage.sh 400 430 scsi0 +10G
#

# Check if the required parameters are provided
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <start_vm_id> <end_vm_id> <disk> <size>"
    exit 1
fi

# Assigning input arguments
START_VM_ID=$1
END_VM_ID=$2
DISK=$3
SIZE=$4

# Loop to resize storage for VMs in the specified range
for (( VMID=START_VM_ID; VMID<=END_VM_ID; VMID++ )); do
    # Check if the VM exists
    if qm status $VMID &>/dev/null; then
        echo "Resizing storage for VM ID: $VMID"

        # Resize the specified disk
        qm resize $VMID $DISK $SIZE
        echo " - Disk $DISK resized by $SIZE for VM ID: $VMID."
    else
        echo "VM ID: $VMID does not exist. Skipping..."
    fi

done

echo "Storage resize process completed!"