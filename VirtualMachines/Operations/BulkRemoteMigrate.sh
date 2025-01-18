#!/bin/bash
#
# This script migrates virtual machines (VMs) from a local Proxmox node to a target Proxmox node.
# It utilizes the Proxmox API for migration and requires proper authentication using an API token.
# The script removes any existing Cloud-Init drives before initiating the migration and adjusts VM IDs based on a provided offset.
#
# Usage:
# ./BulkRemoteMigrate.sh <target_host> <api_token> <fingerprint> <target_storage> <vm_offset> <target_network>
# Where:
#   target_host - The hostname or IP address of the target Proxmox server.
#   api_token - The API token used for authentication.
#   fingerprint - The SSL fingerprint of the target Proxmox server.
#   target_storage - The storage identifier on the target node where VMs will be stored.
#   vm_offset - An integer value to offset the VM IDs to avoid conflicts.
#   target_network - The network bridge on the target server to connect the VMs.
#

# Assigning input arguments
TARGET_HOST="$1"
API_TOKEN="apitoken=$2"
FINGERPRINT="$3"
TARGET_STORAGE="$4"
VM_OFFSET="$5"
TARGET_NETWORK="$6"

# Proxmox API Token and host information
echo "Using target host: $TARGET_HOST"
echo "Using API token: $API_TOKEN"
echo "Using fingerprint: $FINGERPRINT"
echo "Using target storage: $TARGET_STORAGE"
echo "VM offset: $VM_OFFSET"
echo "Target network: $TARGET_NETWORK"

VM_IDS=$(qm list | awk 'NR>1 {print $1}') # all on local node

for VM_ID in $VM_IDS; do
    # Calculate target VM ID
    TARGET_VM_ID=$((VM_ID + VM_OFFSET))

    # Delete the Cloud-Init drive (ide2) if it exists
    echo "Removing Cloud-Init drive (ide2) for VM ID $VM_ID..."
    qm set $VM_ID --delete ide2

    # Determine target bridge based on input network
    TARGET_BRIDGE="$TARGET_NETWORK"

    # Command to migrate VM
    MIGRATE_CMD="qm remote-migrate $VM_ID $TARGET_VM_ID '$API_TOKEN,host=$TARGET_HOST,fingerprint=$FINGERPRINT' --target-bridge $TARGET_BRIDGE --target-storage $TARGET_STORAGE --online"

    echo "Migrating VM ID $VM_ID to VM ID $TARGET_VM_ID on target node..."
    echo "Using command: $MIGRATE_CMD"

    # Execute migration
    eval $MIGRATE_CMD

    # Wait for the command to finish
    wait

    echo "Migration of VM ID $VM_ID completed."
done

echo "All specified VMs have been attempted for migration."
