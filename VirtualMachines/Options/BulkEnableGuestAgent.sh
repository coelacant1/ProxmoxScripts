#!/bin/bash
#
# This script enables the QEMU guest agent for a range of virtual machines (VMs) within a Proxmox VE environment.
# Optionally, it can restart the VMs after enabling the guest agent.
#
# Usage:
# ./EnableGuestAgent.sh <start_vm_id> <end_vm_id> [restart]
#
# Arguments:
#   start_vm_id - The ID of the first VM to update.
#   end_vm_id - The ID of the last VM to update.
#   restart - Optional. Set to 'restart' to restart the VMs after enabling the guest agent.
#
# Example:
#   ./EnableGuestAgent.sh 400 430
#   ./EnableGuestAgent.sh 400 430 restart
#

# Check if the required parameters are provided
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <start_vm_id> <end_vm_id> [restart]"
    exit 1
fi

# Assigning input arguments
START_VM_ID=$1
END_VM_ID=$2
RESTART_OPTION=${3:-}

# Loop to enable QEMU guest agent for VMs in the specified range
for (( VMID=START_VM_ID; VMID<=END_VM_ID; VMID++ )); do
    # Check if the VM exists
    if qm status $VMID &>/dev/null; then
        echo "Enabling QEMU guest agent for VM ID: $VMID"

        # Enable the QEMU guest agent
        qm set $VMID --agent 1
        echo " - QEMU guest agent enabled for VM ID: $VMID."

        # Optionally restart the VM if the 'restart' option is provided
        if [ "$RESTART_OPTION" == "restart" ]; then
            echo "Restarting VM ID: $VMID"
            qm restart $VMID
            echo " - VM ID: $VMID restarted."
        fi
    else
        echo "VM ID: $VMID does not exist. Skipping..."
    fi

done

echo "QEMU guest agent enable process completed!"