#!/bin/bash
#
# BulkChangeUserPass.sh
#
# This script updates the Cloud-Init username and password for a range of 
# virtual machines (VMs) within a Proxmox VE environment. It allows you to
# set a new username (optional) and password (required) for each VM, then 
# regenerates the Cloud-Init image to apply the changes.
#
# Usage:
#   ./BulkChangeUserPass.sh <start_vm_id> <end_vm_id> <password> [username]
#
# Examples:
#   # Update VMs 400 through 430 with a new password and new username
#   ./BulkChangeUserPass.sh 400 430 myNewPassword newuser
#
#   # Update VMs 400 through 430 with a new password only, preserving the existing username
#   ./BulkChangeUserPass.sh 400 430 myNewPassword
#
source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Validate environment
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Assigning input arguments
###############################################################################
if [ "$#" -lt 3 ]; then
    echo "Error: Missing required parameters."
    echo "Usage: $0 <start_vm_id> <end_vm_id> <password> [username]"
    exit 1
fi

START_VMID="$1"
END_VMID="$2"
PASSWORD="$3"
USERNAME="${4:-}"

###############################################################################
# Update Cloud-Init settings for each VM in the specified range
###############################################################################
for (( VMID=START_VMID; VMID<=END_VMID; VMID++ )); do
    if qm status "$VMID" &>/dev/null; then
        echo "Updating Cloud-Init settings for VM ID: $VMID"
        qm set "$VMID" --ciuser "$USERNAME" --cipassword "$PASSWORD"
        qm cloudinit dump "$VMID"
        echo " - Cloud-Init username and password updated for VM ID: $VMID."
    else
        echo "VM ID: $VMID does not exist. Skipping..."
    fi
done

echo "Cloud-Init user and password update process completed!"
