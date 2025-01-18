#!/bin/bash
#
# This script is designed for batch management of virtual machines (VMs) on a Proxmox VE environment.
# It takes a range of VM IDs and performs three actions: unprotects, stops, and destroys each VM in the range.
# This script is useful for cleaning up VMs in a controlled manner, ensuring that all VMs within the specified
# range are properly shut down and removed from the system. Caution is advised, as this will permanently delete VMs.
#
# Usage:
# ./BulkDelete.sh start_vmid stop_vmid
#   start_vmid - The starting VM ID from which the batch operation begins.
#   stop_vmid - The ending VM ID up to which the batch operation is performed.
#
# Example:
#   ./BulkDelete.sh 600 650
#

# Check if input arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 start_vmid stop_vmid"
    echo "Example: $0 600 650"
    exit 1
fi

START_VMID=$1
STOP_VMID=$2

# Main loop through the specified range of VMIDs
for vmid in $(seq $START_VMID $STOP_VMID); do
    qm set $vmid --protection 0
    qm stop $vmid
    qm destroy $vmid
done

echo "Operation completed for all specified VMs."
