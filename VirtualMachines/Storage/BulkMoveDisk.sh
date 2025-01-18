#!/bin/bash
#
# This script facilitates the migration of virtual machine (VM) disks across different storage backends on a Proxmox VE environment.
# It iterates over a specified range of VM IDs and moves their primary disks (assumed to be 'sata0') to a designated target storage.
# This is useful for managing storage utilization, upgrading to new storage hardware, or balancing loads across different storage systems.
#
# Usage:
# ./VMMoveDisk.sh start_vmid stop_vmid target_storage
#   start_vmid - The starting VM ID from which disk migration begins.
#   stop_vmid - The ending VM ID up to which disk migration is performed.
#   target_storage - The identifier of the target storage where disks will be moved.
#
# Example:
#   ./VMMoveDisk.sh 101 105 local-lvm
#
# Function Index:
#   - move_disk
#

# Usage Information
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 start_vmid stop_vmid target_storage"
    echo "Example: $0 101 105 local-lvm"
    exit 1
fi

START_VMID=$1
STOP_VMID=$2
TARGET_STORAGE=$3

# Function to move a disk
move_disk() {
    local vmid=$1
    local storage=$2

    echo "Moving disk of VM $vmid to storage $storage..."
    qm move-disk $vmid sata0 $storage

    if [ $? -eq 0 ]; then
        echo "Disk move successful for VMID $vmid"
    else
        echo "Failed to move disk for VMID $vmid"
    fi
}

# Main loop through the specified range of VMIDs
for (( vmid=$START_VMID; vmid<=$STOP_VMID; vmid++ ))
do
    move_disk $vmid $TARGET_STORAGE
done

echo "Disk move process completed for all specified VMs."
