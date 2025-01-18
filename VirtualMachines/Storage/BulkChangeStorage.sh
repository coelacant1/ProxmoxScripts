#!/bin/bash
#
# This script automates the process of updating the storage location specified in the configuration
# files of virtual machines (VMs) on a Proxmox server. It is designed to bulk-update the storage
# paths for a range of VM IDs from one storage location to another. This can be useful in scenarios
# where VMs need to be moved to a different storage solution or when reorganizing storage resources.
#
# Usage:
# ./BulkChangeStorage.sh <start_id> <end_id> <hostname> <current_storage> <new_storage>
#   start_id - The starting VM ID for the operation.
#   end_id - The ending VM ID for the operation.
#   hostname - The hostname of the Proxmox node where the VMs are configured.
#   current_storage - The current identifier of the storage used in the VMs' configuration.
#   new_storage - The new identifier of the storage to replace the current one.
#
# Example:
#   ./BulkChangeStorage.sh 100 200 pve-node1 local-lvm local-zfs
#

# Check if required inputs are provided
if [ $# -lt 5 ]; then
    echo "Usage: $0 <start_id> <end_id> <hostname> <current_storage> <new_storage>"
    exit 1
fi

START_ID=$1
END_ID=$2
HOST_NAME=$3
CURRENT_STORAGE=$4
NEW_STORAGE=$5

# Loop through the VM IDs
for VMID in $(seq $START_ID $END_ID); do
    CONFIG_FILE="/etc/pve/nodes/${HOST_NAME}/qemu-server/${VMID}.conf"

    # Check if the VM config file exists
    if [ -f "$CONFIG_FILE" ]; then
        echo "Processing VM ID: $VMID"

        # Check and replace the storage
        if grep -q "$CURRENT_STORAGE" "$CONFIG_FILE"; then
            sed -i "s/$CURRENT_STORAGE/$NEW_STORAGE/g" "$CONFIG_FILE"
            echo " - Storage location changed from $CURRENT_STORAGE to $NEW_STORAGE."
        else
            echo " - $CURRENT_STORAGE not found in disk configuration. No changes made."
        fi
    else
        echo "VM ID: $VMID does not exist. Skipping..."
    fi
done
