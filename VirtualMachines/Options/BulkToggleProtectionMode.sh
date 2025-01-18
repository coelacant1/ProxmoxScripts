#!/bin/bash
#
# This script toggles the protection mode for a range of virtual machines (VMs) within a Proxmox VE environment.
#
# Usage:
# ./ToggleProtectionMode.sh <start_vm_id> <end_vm_id> <enable|disable>
#
# Arguments:
#   start_vm_id - The ID of the first VM to update.
#   end_vm_id - The ID of the last VM to update.
#   enable|disable - Set to 'enable' to enable protection, or 'disable' to disable it.
#
# Example:
#   ./ToggleProtectionMode.sh 400 430 enable
#   ./ToggleProtectionMode.sh 400 430 disable
#

# Check if the required parameters are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <start_vm_id> <end_vm_id> <enable|disable>"
    exit 1
fi

# Assigning input arguments
START_VM_ID=$1
END_VM_ID=$2
ACTION=$3

# Determine the appropriate setting based on the action
if [ "$ACTION" == "enable" ]; then
    PROTECTION_SETTING="1"
elif [ "$ACTION" == "disable" ]; then
    PROTECTION_SETTING="0"
else
    echo "Invalid action: $ACTION. Use 'enable' or 'disable'."
    exit 1
fi

# Loop to update protection mode for VMs in the specified range
for (( VMID=START_VM_ID; VMID<=END_VM_ID; VMID++ )); do
    # Check if the VM exists
    if qm status $VMID &>/dev/null; then
        echo "Updating protection mode for VM ID: $VMID"

        # Set the protection mode
        qm set $VMID --protection $PROTECTION_SETTING
        echo " - Protection mode set to '$ACTION' for VM ID: $VMID."
    else
        echo "VM ID: $VMID does not exist. Skipping..."
    fi

done

echo "Protection mode toggle process completed!"
