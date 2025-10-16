#!/bin/bash
#
# BulkUnmountISOs.sh
#
# Unmounts all ISO images from CD/DVD drives for a range of virtual machines (VMs) within a Proxmox VE environment.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkUnmountISOs.sh <start_vm_id> <end_vm_id>
#
# Arguments:
#   start_vm_id - The ID of the first VM to update.
#   end_vm_id   - The ID of the last VM to update.
#
# Examples:
#   ./BulkUnmountISOs.sh 400 430
#
# Function Index:
#   - usage
#   - parse_args
#   - unmount_isos
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
Usage: ${0##*/} <start_vm_id> <end_vm_id>

Unmounts ISO images from CD/DVD drives for a range of VMs.

Arguments:
  start_vm_id - The ID of the first VM to update
  end_vm_id   - The ID of the last VM to update
Examples:
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    START_VM_ID="$1"
    END_VM_ID="$2"
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

# --- unmount_isos ------------------------------------------------------------
# @function unmount_isos
# @description Unmounts ISOs from all CD/DVD drives for a VM.
# @param 1 VM ID
# @param 2 Target node name
unmount_isos() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping on ${node}"
        return 0
    fi
    
    __update__ "Unmounting ISOs for VM ${vmid}... on ${node}"
    
    # Get all CD/DVD drives for the VM
    local drives
    drives=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -oP '(ide|sata|scsi|virtio)\d+(?=:.*media=cdrom)' || true)
    
    if [[ -z "$drives" ]]; then
        __update__ "No CD/DVD drives found for VM ${vmid} on ${node}"
        return 0
    fi
    
    local unmounted=0
    local failed=0
    while IFS= read -r drive; do
        if [[ -n "$drive" ]]; then
            if qm set "$vmid" --"$drive" none,media=cdrom --node "$node" 2>/dev/null; then
                ((unmounted++))
            else
                ((failed++))
            fi
        fi
    done <<< "$drives"
    
    if (( failed > 0 )); then
        __err__ "Failed to unmount ${failed} drive(s) for VM ${vmid}"
        return 1
    elif (( unmounted > 0 )); then
        __ok__ "Unmounted ${unmounted} ISO(s) from VM ${vmid} on ${node}"
    else
        __update__ "No ISOs to unmount for VM ${vmid} on ${node}"
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and unmounts ISOs.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk unmount ISOs: VMs ${START_VM_ID} to ${END_VM_ID} (cluster-wide)"
        # Unmount ISOs for VMs in the specified range
    local failed_count=0
    local processed_count=0
    for (( vmid=START_VM_ID; vmid<=END_VM_ID; vmid++ )); do

        if unmount_isos "$vmid"; then

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
        __ok__ "ISO unmount process completed successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, converted to cluster-wide