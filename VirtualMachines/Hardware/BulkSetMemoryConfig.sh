#!/bin/bash
#
# BulkSetMemoryConfig.sh
#
# Sets the amount of memory allocated to a range of virtual machines (VMs) within a Proxmox VE environment.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkSetMemoryConfig.sh <start_vm_id> <end_vm_id> <memory_size>
#
# Arguments:
#   start_vm_id - The ID of the first VM to update.
#   end_vm_id   - The ID of the last VM to update.
#   memory_size - The amount of memory (in MB) to allocate to each VM.
#
# Examples:
#   ./BulkSetMemoryConfig.sh 400 430 8192
#
# Function Index:
#   - usage
#   - parse_args
#   - set_memory
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
Usage: ${0##*/} <start_vm_id> <end_vm_id> <memory_size>

Sets memory allocation for a range of VMs.

Arguments:
  start_vm_id - The ID of the first VM to update
  end_vm_id   - The ID of the last VM to update
  memory_size - Memory size in MB
Examples:
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 3 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    START_VM_ID="$1"
    END_VM_ID="$2"
    MEMORY_SIZE="$3"
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
    
    # Validate memory size is numeric
    if ! [[ "$MEMORY_SIZE" =~ ^[0-9]+$ ]]; then
        __err__ "Memory size must be numeric (in MB)"
        exit 64
    fi
}

# --- set_memory --------------------------------------------------------------
# @function set_memory
# @description Sets memory allocation for a VM.
# @param 1 VM ID
# @param 2 Target node name
set_memory() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping on ${node}"
        return 0
    fi
    
    __update__ "Setting memory to ${MEMORY_SIZE}MB for VM ${vmid}... on ${node}"
    if qm set "$vmid" --memory "$MEMORY_SIZE" --node "$node" 2>/dev/null; then
        __ok__ "Memory set to ${MEMORY_SIZE}MB for VM ${vmid} on ${node}"
    else
        __err__ "Failed to set memory for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and sets memory.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk set memory: VMs ${START_VM_ID} to ${END_VM_ID} (cluster-wide)"
    __info__ "Memory: ${MEMORY_SIZE}MB"
        # Set memory for VMs in the specified range
    local failed_count=0
    local processed_count=0
    for (( vmid=START_VM_ID; vmid<=END_VM_ID; vmid++ )); do

        if set_memory "$vmid"; then

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
        __ok__ "Memory configuration updated successfully for all VMs"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, converted to cluster-wide