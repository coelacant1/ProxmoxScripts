#!/bin/bash
#
# BulkStart.sh
#
# Starts a range of virtual machines (VMs) within a Proxmox VE environment.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkStart.sh <first_vm_id> <last_vm_id>
#
# Arguments:
#   first_vm_id - The ID of the first VM to start.
#   last_vm_id  - The ID of the last VM to start.
#
# Examples:
#   ./BulkStart.sh 400 430
#   This will start VMs 400-430 regardless of which nodes they are on
#
# Function Index:
#   - usage
#   - parse_args
#   - start_vm
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
usage() {
    cat <<-USAGE
Usage: ${0##*/} <first_vm_id> <last_vm_id>

Starts a range of VMs across the entire cluster.
Automatically detects which node each VM is on.

Arguments:
  first_vm_id  - The ID of the first VM to start
  last_vm_id   - The ID of the last VM to start

Examples:
  ${0##*/} 400 430
USAGE
}

# --- parse_args --------------------------------------------------------------
parse_args() {
    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    FIRST_VM_ID="$1"
    LAST_VM_ID="$2"

    if ! [[ "$FIRST_VM_ID" =~ ^[0-9]+$ ]] || ! [[ "$LAST_VM_ID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    if (( FIRST_VM_ID > LAST_VM_ID )); then
        __err__ "First VM ID must be less than or equal to last VM ID"
        exit 64
    fi
}

# --- start_vm ----------------------------------------------------------------
start_vm() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    __update__ "Starting VM ${vmid} on node ${node}..."
    if qm start "$vmid" --node "$node" 2>/dev/null; then
        __ok__ "VM ${vmid} started successfully on ${node}"
    else
        __err__ "Failed to start VM ${vmid} on ${node}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk start (cluster-wide): VMs ${FIRST_VM_ID} to ${LAST_VM_ID}"
    
    local failed_count=0
    local processed_count=0
    
    for (( vm_id=FIRST_VM_ID; vm_id<=LAST_VM_ID; vm_id++ )); do
        if start_vm "$vm_id"; then
            ((processed_count++))
        else
            ((failed_count++))
        fi
    done
    
    __info__ "Processed ${processed_count} VM(s)"
    
    if (( failed_count > 0 )); then
        __err__ "Start completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "All VMs started successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated with cluster-wide auto-detection