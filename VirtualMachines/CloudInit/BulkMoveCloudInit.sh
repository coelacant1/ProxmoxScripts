#!/bin/bash
#
# This script automates the migration of Cloud-Init disks for LXC containers or VMs within a Proxmox VE environment.
# It allows bulk migration by specifying a range of VM IDs or selecting all VMs.
# The script backs up existing Cloud-Init parameters, deletes the current Cloud-Init disk, and recreates it on the target storage.
# This is particularly useful for reorganizing storage resources or moving Cloud-Init configurations to a different storage backend.
#
# Usage:
# ./BulkMoveCloudInit.sh <start_vmid|ALL> <end_vmid|target_storage> [target_storage]
#
# Arguments:
#   start_vmid      - The starting VM ID for migration. Use "ALL" to target all VMs.
#   end_vmid        - If start_vmid is a number, this is the ending VM ID for migration.
#                     If start_vmid is "ALL", this argument becomes the target storage.
#   target_storage  - (Optional) The target storage for the Cloud-Init disk. Required if start_vmid is not "ALL".
#
# Examples:
#   ./BulkMoveCloudInit.sh 100 200 local-lvm
#   This command will migrate Cloud-Init disks for VMs with IDs from 100 to 200 to the "local-lvm" storage.
#
#   ./BulkMoveCloudInit.sh ALL ceph-storage
#   This command will migrate Cloud-Init disks for all VMs to the "ceph-storage" storage.
#
# Important Notes:
#   - Ensure that the target storage exists and has sufficient space.
#   - The script assumes that the Cloud-Init disk is attached as "sata1". Modify the script if your setup differs.
#   - Always back up your VM configurations before performing bulk operations.
#   - Execute the script with appropriate permissions (typically as root or a user with sufficient privileges).
#
# Permissions and Execution:
#   Ensure the script has execute permissions:
#     chmod +x BulkMoveCloudInit.sh
#   Execute the script as shown in the usage examples.
# Function Index:
#   - usage
#   - check_storage_exists
#   - get_current_storage
#   - migrate_cloud_init_disk
#

# Exit immediately if a command exits with a non-zero status
set -e

# Function to display usage information
usage() {
    echo "Usage: $0 <start_vmid|ALL> <end_vmid|target_storage> [target_storage]"
    echo
    echo "Arguments:"
    echo "  start_vmid      - The starting VM ID for migration. Use 'ALL' to target all VMs."
    echo "  end_vmid        - If start_vmid is a number, this is the ending VM ID for migration."
    echo "                   If start_vmid is 'ALL', this argument becomes the target storage."
    echo "  target_storage  - (Optional) The target storage for the Cloud-Init disk."
    echo
    echo "Examples:"
    echo "  $0 100 200 local-lvm"
    echo "  $0 ALL ceph-storage"
}

# Function to check if a storage exists
check_storage_exists() {
    local storage=$1
    if ! pvesh get /storage | grep -qw "$storage"; then
        echo "Error: Storage '$storage' does not exist."
        exit 1
    fi
}

# Function to get the current Cloud-Init disk storage
get_current_storage() {
    local vmid=$1
    # Attempt to find the Cloud-Init disk (commonly attached as sata1 or ide2)
    local storage
    storage=$(qm config "$vmid" | grep -E 'sata1:|ide2:' | awk -F ':' '{print $2}' | awk -F',' '{print $1}' | awk -F' ' '{print $1}')
    echo "$storage"
}

# Function to migrate the Cloud-Init disk
migrate_cloud_init_disk() {
    local vmid=$1

    echo "Processing VM ID: $vmid"

    # Check if the VM exists
    if ! qm list | awk 'NR>1 {print $1}' | grep -qw "^$vmid$"; then
        echo "VM ID $vmid does not exist. Skipping."
        return
    fi

    # Get current Cloud-Init disk storage
    CURRENT_STORAGE=$(get_current_storage "$vmid")

    if [ -z "$CURRENT_STORAGE" ]; then
        echo "VM $vmid does not have a Cloud-Init disk attached. Skipping."
        return
    fi

    # Check if the Cloud-Init disk is already on the target storage
    if [ "$CURRENT_STORAGE" == "$TARGET_STORAGE" ]; then
        echo "Cloud-Init disk for VM $vmid is already on $TARGET_STORAGE. Skipping migration."
        return
    fi

    # Backup Cloud-Init parameters
    echo "Backing up Cloud-Init parameters for VM $vmid..."
    CI_USER=$(qm config "$vmid" | grep -oP '(?<=^ciuser: ).*')
    CI_PASSWORD=$(qm config "$vmid" | grep -oP '(?<=^cipassword: ).*')
    CI_IPCONFIG=$(qm config "$vmid" | grep -oP '(?<=^ipconfig0: ).*')
    CI_NAMESERVER=$(qm config "$vmid" | grep -oP '(?<=^nameserver: ).*')
    CI_SEARCHDOMAIN=$(qm config "$vmid" | grep -oP '(?<=^searchdomain: ).*')
    CI_SSHKEYS=$(qm config "$vmid" | grep -oP '(?<=^sshkeys: ).*' | sed 's/%0A/\n/g' | sed 's/%20/ /g')

    if [ -z "$CI_USER" ] && [ -z "$CI_IPCONFIG" ]; then
        echo "VM $vmid does not have Cloud-Init parameters. Skipping migration."
        return
    fi

    echo "Cloud-Init parameters backed up successfully."

    # Delete the existing Cloud-Init disk
    echo "Deleting existing Cloud-Init disk for VM $vmid..."
    qm set "$vmid" --delete sata1 2>/dev/null || qm set "$vmid" --delete ide2

    echo "Cloud-Init disk for VM $vmid deleted successfully."

    # Re-create Cloud-Init disk on the target storage using the same interface
    # Determine which interface was used
    if qm config "$vmid" | grep -q "^sata1:"; then
        CI_INTERFACE="sata1"
    elif qm config "$vmid" | grep -q "^ide2:"; then
        CI_INTERFACE="ide2"
    else
        # Default to sata1 if unable to determine
        CI_INTERFACE="sata1"
    fi

    echo "Re-creating Cloud-Init disk for VM $vmid on $TARGET_STORAGE using interface $CI_INTERFACE..."
    qm set "$vmid" --"${CI_INTERFACE%%[0-9]*}" "$TARGET_STORAGE:cloudinit"

    echo "Cloud-Init disk for VM $vmid created successfully on $TARGET_STORAGE."

    # Restore Cloud-Init parameters
    echo "Restoring Cloud-Init parameters for VM $vmid..."

    # Prepare SSH keys if they exist and are valid
    if [[ -n "$CI_SSHKEYS" && "$CI_SSHKEYS" =~ ^ssh-(rsa|dss|ed25519|ecdsa) ]]; then
        TEMP_SSH_FILE=$(mktemp)
        echo -e "$CI_SSHKEYS" > "$TEMP_SSH_FILE"
        SSHKEYS_OPTION="sshkeys=$(cat "$TEMP_SSH_FILE")"
    else
        SSHKEYS_OPTION=""
        echo "No valid SSH keys found for VM $vmid. Skipping SSH key restoration."
    fi

    # Apply the restored parameters
    qm set "$vmid" \
        --ciuser "$CI_USER" \
        --cipassword "$CI_PASSWORD" \
        --ipconfig0 "$CI_IPCONFIG" \
        --nameserver "$CI_NAMESERVER" \
        --searchdomain "$CI_SEARCHDOMAIN" \
        ${SSHKEYS_OPTION:+--sshkeys "$SSHKEYS_OPTION"}

    if [ $? -eq 0 ]; then
        echo "Cloud-Init parameters for VM $vmid restored successfully."
    else
        echo "Failed to restore Cloud-Init parameters for VM $vmid."
    fi

    # Clean up temporary SSH key file
    if [ -n "$TEMP_SSH_FILE" ] && [ -f "$TEMP_SSH_FILE" ]; then
        rm "$TEMP_SSH_FILE"
    fi
}

# Check if the minimum required parameters are provided
if [ "$#" -lt 2 ]; then
    usage
    exit 1
fi

# Assign command-line arguments to variables
START_VMID=$1
END_VMID=$2
TARGET_STORAGE=$3

# Determine VM IDs and target storage based on the first argument
if [ "$START_VMID" == "ALL" ]; then
    if [ "$#" -lt 2 ]; then
        echo "Error: When using 'ALL', you must specify the target storage."
        usage
        exit 1
    fi
    VMIDS=$(qm list | awk 'NR>1 {print $1}')
    TARGET_STORAGE=$END_VMID
else
    if [ "$#" -lt 3 ]; then
        echo "Error: When specifying VM ID range, target storage must be provided."
        usage
        exit 1
    fi
    # Validate that START_VMID and END_VMID are integers
    if ! [[ "$START_VMID" =~ ^[0-9]+$ ]] || ! [[ "$END_VMID" =~ ^[0-9]+$ ]]; then
        echo "Error: start_vmid and end_vmid must be positive integers."
        usage
        exit 1
    fi
    VMIDS=$(seq "$START_VMID" "$END_VMID")
fi

# Validate that TARGET_STORAGE exists
check_storage_exists "$TARGET_STORAGE"

# Loop through each VMID and migrate the Cloud-Init disk
for VMID in $VMIDS; do
    migrate_cloud_init_disk "$VMID"
done

echo "Cloud-Init disk migration process completed."
