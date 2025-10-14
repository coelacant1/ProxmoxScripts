#!/bin/bash
#
# BulkDelete.sh
#
# Deletes virtual machines (VMs) within a Proxmox VE cluster by unprotecting, stopping,
# and destroying them. Automatically detects which node each VM is on and executes the
# operation cluster-wide.
#
# WARNING: This script permanently deletes VMs. Use with extreme caution!
#
# Usage:
#   ./BulkDelete.sh <first_vm_id> <last_vm_id>
#
# Arguments:
#   first_vm_id - The ID of the first VM to delete.
#   last_vm_id  - The ID of the last VM to delete.
#
# Examples:
#   ./BulkDelete.sh 600 650
#   This will delete VMs 600-650 regardless of which nodes they are on
#
# Function Index:
#   - usage
#   - parse_args
#   - delete_vm
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

WARNING: Permanently deletes VMs across the entire cluster!

Deletes VMs by unprotecting, stopping, and destroying them.
Automatically detects which node each VM is on.

Arguments:
  first_vm_id  - The ID of the first VM to delete
  last_vm_id   - The ID of the last VM to delete

Examples:
  ${0##*/} 600 650

Safety Features:
  - Confirmation prompt before deletion
  - Progress reporting for each VM
  - Automatic node detection
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

# --- delete_vm ---------------------------------------------------------------
delete_vm() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    __update__ "Deleting VM ${vmid} on node ${node}..."
    
    # Step 1: Unprotect the VM
    if ! qm set "$vmid" --protection 0 --node "$node" 2>/dev/null; then
        __err__ "Failed to unprotect VM ${vmid}"
        return 1
    fi
    
    # Step 2: Stop the VM (force stop if necessary)
    if qm status "$vmid" --node "$node" 2>/dev/null | grep -q "running"; then
        __update__ "Stopping VM ${vmid}..."
        if ! qm stop "$vmid" --node "$node" 2>/dev/null; then
            __update__ "Normal stop failed, forcing stop..."
            qm stop "$vmid" --skiplock --node "$node" 2>/dev/null || true
        fi
        
        # Wait for VM to stop (max 30 seconds)
        local wait_count=0
        while qm status "$vmid" --node "$node" 2>/dev/null | grep -q "running"; do
            sleep 1
            ((wait_count++))
            if (( wait_count > 30 )); then
                __update__ "VM ${vmid} did not stop in time, proceeding anyway..."
                break
            fi
        done
    fi
    
    # Step 3: Destroy the VM
    if qm destroy "$vmid" --skiplock --node "$node" 2>/dev/null; then
        __ok__ "VM ${vmid} deleted successfully from ${node}"
        return 0
    else
        __err__ "Failed to destroy VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    
    __warn__ "WARNING: This will permanently delete VMs ${FIRST_VM_ID} to ${LAST_VM_ID}"
    __warn__ "This operation cannot be undone!"
    
    # Confirm before proceeding
    if ! __prompt_yes_no__ "Are you absolutely sure you want to delete these VMs?"; then
        __info__ "Deletion cancelled by user"
        exit 0
    fi
    
    __info__ "Bulk delete (cluster-wide): VMs ${FIRST_VM_ID} to ${LAST_VM_ID}"
    
    local failed_count=0
    local processed_count=0
    local skipped_count=0
    
    for (( vm_id=FIRST_VM_ID; vm_id<=LAST_VM_ID; vm_id++ )); do
        # Check if VM exists
        local node
        node=$(__get_vm_node__ "$vm_id")
        
        if [[ -z "$node" ]]; then
            ((skipped_count++))
            continue
        fi
        
        if delete_vm "$vm_id"; then
            ((processed_count++))
        else
            ((failed_count++))
        fi
    done
    
    __info__ "Deletion summary:"
    __info__ "  Deleted: ${processed_count}"
    __info__ "  Skipped: ${skipped_count}"
    __info__ "  Failed: ${failed_count}"
    
    if (( failed_count > 0 )); then
        __err__ "Deletion completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "All VMs deleted successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Converted to cluster-wide with safety features
