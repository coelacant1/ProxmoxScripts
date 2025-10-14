#!/bin/bash
#
# BulkMoveDisk.sh
#
# Facilitates migration of VM disks across different storage backends on a Proxmox VE environment.
# Iterates over a specified range of VM IDs and moves their primary disks to designated target storage.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkMoveDisk.sh <start_vmid> <stop_vmid> <disk> <target_storage>
#
# Arguments:
#   start_vmid      - The starting VM ID from which disk migration begins.
#   stop_vmid       - The ending VM ID up to which disk migration is performed.
#   disk            - The disk identifier to move (e.g., 'sata0', 'scsi0', 'virtio0').
#   target_storage  - The identifier of the target storage where disks will be moved.
#
# Examples:
#   ./BulkMoveDisk.sh 101 105 sata0 local-lvm
#
# Function Index:
#   - usage
#   - parse_args
#   - move_disk
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- usage -------------------------------------------------------------------
# @function usage
# @description Prints usage information and exits.
usage() {
    cat <<-USAGE
Usage: ${0##*/} <start_vmid> <stop_vmid> <disk> <target_storage>

Moves VM disks to different storage.

Arguments:
  start_vmid      - Starting VM ID
  stop_vmid       - Ending VM ID
  disk            - Disk identifier (e.g., 'sata0', 'scsi0', 'virtio0')
  target_storage  - Target storage identifier
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

    START_VMID="$1"
    STOP_VMID="$2"
    DISK="$3"
    TARGET_STORAGE="$4"
    # Validate VM IDs are numeric
    if ! [[ "$START_VMID" =~ ^[0-9]+$ ]] || ! [[ "$STOP_VMID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    # Validate range
    if (( START_VMID > STOP_VMID )); then
        __err__ "Start VM ID must be less than or equal to stop VM ID"
        exit 64
    fi
}

# --- move_disk ---------------------------------------------------------------
# @function move_disk
# @description Moves a disk for a VM to the target storage.
# @param 1 VM ID
# @param 2 Target node name
move_disk() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping on ${node}"
        return 0
    fi
    
    __update__ "Moving disk ${DISK} of VM ${vmid} to storage ${TARGET_STORAGE}... on ${node}"
    if qm move-disk "$vmid" "$DISK" "$TARGET_STORAGE" --node "$node" 2>/dev/null; then
        __ok__ "Disk moved successfully for VM ${vmid} on ${node}"
    else
        __err__ "Failed to move disk for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and moves disks.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk move disk: VMs ${START_VMID} to ${STOP_VMID} (cluster-wide)"
    __info__ "Moving ${DISK} to ${TARGET_STORAGE}"
        # Move disks for VMs in the specified range
    local failed_count=0
    local processed_count=0
    for (( vmid=START_VMID; vmid<=STOP_VMID; vmid++ )); do

        if move_disk "$vmid"; then

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
        __ok__ "All disk moves completed successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, converted to cluster-wide
