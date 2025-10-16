#!/bin/bash
#
# BulkResizeStorage.sh
#
# Resizes storage for a range of virtual machines (VMs) within a Proxmox VE environment.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkResizeStorage.sh <start_vm_id> <end_vm_id> <disk> <size>
#
# Arguments:
#   start_vm_id  - The ID of the first VM to update.
#   end_vm_id    - The ID of the last VM to update.
#   disk         - The disk to resize (e.g., 'scsi0', 'virtio0', 'sata0').
#   size         - The size change (e.g., '+10G' to add 10GB).
#
# Examples:
#   ./BulkResizeStorage.sh 400 430 scsi0 +10G
#
# Function Index:
#   - usage
#   - parse_args
#   - resize_storage
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- usage -------------------------------------------------------------------
# @function usage
# @description Prints usage information and exits.
usage() {
    cat <<-USAGE
Usage: ${0##*/} <start_vm_id> <end_vm_id> <disk> <size>

Resizes storage for a range of VMs.

Arguments:
  start_vm_id  - The ID of the first VM to update
  end_vm_id    - The ID of the last VM to update
  disk         - Disk to resize (e.g., 'scsi0', 'virtio0', 'sata0')
  size         - Size change (e.g., '+10G' to add 10GB)
Examples:
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 4 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    START_VM_ID="$1"
    END_VM_ID="$2"
    DISK="$3"
    SIZE="$4"
    # Validate VM IDs are numeric
    if ! [[ "$START_VM_ID" =~ ^[0-9]+$ ]] || ! [[ "$END_VM_ID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    # Validate range
    if (( START_VM_ID > END_VM_ID )); then
        __err__ "Start VM ID must be less than or equal to end VM ID"
        exit 64
    fi
}

# --- resize_storage ----------------------------------------------------------
# @function resize_storage
# @description Resizes storage for a VM.
# @param 1 VM ID
# @param 2 Target node name
resize_storage() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping on ${node}"
        return 0
    fi
    
    __update__ "Resizing disk ${DISK} by ${SIZE} for VM ${vmid}... on ${node}"
    if qm resize "$vmid" "$DISK" "$SIZE" --node "$node" 2>/dev/null; then
        __ok__ "Disk ${DISK} resized by ${SIZE} for VM ${vmid} on ${node}"
    else
        __err__ "Failed to resize disk for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and resizes storage.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk resize storage: VMs ${START_VM_ID} to ${END_VM_ID} (cluster-wide)"
    __info__ "Resizing ${DISK} by ${SIZE}"
        # Resize storage for VMs in the specified range
    local failed_count=0
    local processed_count=0
    for (( vmid=START_VM_ID; vmid<=END_VM_ID; vmid++ )); do

        if resize_storage "$vmid"; then

            ((processed_count++))

        else

            ((failed_count++))

        fi

    done
    
    __info__ "Processed ${processed_count} VM(s)"
    
    
    
    if (( failed_count > 0 )); then
        __err__ "Operation completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "All storage resizes completed successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, converted to cluster-wide