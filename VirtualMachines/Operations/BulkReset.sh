#!/bin/bash
#
# BulkReset.sh
#
# Resets a range of virtual machines (VMs) within a Proxmox VE environment.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkReset.sh <first_vm_id> <last_vm_id>
#
# Arguments:
#   first_vm_id - The ID of the first VM to reset.
#   last_vm_id  - The ID of the last VM to reset.
#
# Examples:
#   ./BulkReset.sh 400 430
#   This will reset VMs 400-430 regardless of which nodes they are on
#
# Function Index:
#   - usage
#   - parse_args
#   - reset_vm
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
Usage: ${0##*/} <first_vm_id> <last_vm_id>

Resets a range of VMs across the entire cluster.
Automatically detects which node each VM is on.

Arguments:
  first_vm_id  - The ID of the first VM to reset
  last_vm_id   - The ID of the last VM to reset

Examples:
  ${0##*/} 400 430
  This will reset VMs 400-430 on any nodes in the cluster
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

    FIRST_VM_ID="$1"
    LAST_VM_ID="$2"

    # Validate VM IDs are numeric
    if ! [[ "$FIRST_VM_ID" =~ ^[0-9]+$ ]] || ! [[ "$LAST_VM_ID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    # Validate range
    if (( FIRST_VM_ID > LAST_VM_ID )); then
        __err__ "First VM ID must be less than or equal to last VM ID"
        exit 64
    fi
}

# --- reset_vm ----------------------------------------------------------------
# @function reset_vm
# @description Resets a VM on its detected node.
# @param 1 VM ID to reset
reset_vm() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    __update__ "Resetting VM ${vmid} on node ${node}..."
    if qm reset "$vmid" --node "$node" 2>/dev/null; then
        __ok__ "VM ${vmid} reset successfully on ${node}"
    else
        __err__ "Failed to reset VM ${vmid} on ${node}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and resets each.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk reset (cluster-wide): VMs ${FIRST_VM_ID} to ${LAST_VM_ID}"
    
    # Reset VMs in the specified range
    local failed_count=0
    local processed_count=0
    
    for (( vm_id=FIRST_VM_ID; vm_id<=LAST_VM_ID; vm_id++ )); do
        if reset_vm "$vm_id"; then
            ((processed_count++))
        else
            ((failed_count++))
        fi
    done
    
    __info__ "Processed ${processed_count} VM(s)"
    
    if (( failed_count > 0 )); then
        __err__ "Reset completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "All VMs reset successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines with cluster-wide auto-detection