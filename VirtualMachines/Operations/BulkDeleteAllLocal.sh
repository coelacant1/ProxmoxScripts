#!/bin/bash
#
# This script deletes all virtual machines (VMs) currently listed on this Proxmox machine.
# It performs three actions for each VM: unprotects, stops, and destroys them.
# WARNING: This script will permanently delete all VMs on the Proxmox machine.
#
# Usage:
# ./BulkDeleteAllLocal.sh
#

# Fetch the list of all VM IDs
VM_IDS=$(qm list | awk 'NR>1 {print $1}')

if [ -z "$VM_IDS" ]; then
    echo "No VMs found on this Proxmox machine."
    exit 0
fi

# Confirm action before proceeding
echo "WARNING: This will delete the following VMs permanently:"
echo "$VM_IDS"
read -p "Are you sure you want to proceed? Type 'yes' to continue: " CONFIRMATION

if [ "$CONFIRMATION" != "yes" ]; then
    echo "Operation canceled."
    exit 0
fi

# Iterate through each VM ID and delete it
for vmid in $VM_IDS; do
    echo "Processing VM ID: $vmid"
    qm set $vmid --protection 0
    qm stop $vmid
    qm destroy $vmid
    echo "VM ID $vmid has been deleted."
done

echo "All VMs have been deleted successfully."