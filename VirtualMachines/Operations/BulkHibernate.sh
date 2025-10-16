#!/bin/bash
#
# BulkHibernate.sh
#
# Hibernates a range of virtual machines (VMs) within a Proxmox VE environment.
# Hibernation saves the VM's RAM state to disk and stops the VM, allowing for fast resume.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkHibernate.sh <first_vm_id> <last_vm_id>
#
# Arguments:
#   first_vm_id - The ID of the first VM to hibernate.
#   last_vm_id  - The ID of the last VM to hibernate.
#
# Examples:
#   ./BulkHibernate.sh 400 430
#   This will hibernate VMs 400-430 regardless of which nodes they are on
#
# Notes:
#   - VMs must have sufficient disk space to store RAM state
#   - Hibernation may take time depending on RAM size
#   - Use BulkStart.sh or BulkResume.sh to restore hibernated VMs
#
# Function Index:
#   - usage
#   - parse_args
#   - hibernate_vm
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- usage -------------------------------------------------------------------
usage() {
    cat <<-USAGE
Usage: ${0##*/} <first_vm_id> <last_vm_id>

Hibernates a range of VMs across the entire cluster.
Saves RAM state to disk for fast resume.
Automatically detects which node each VM is on.

Arguments:
  first_vm_id  - The ID of the first VM to hibernate
  last_vm_id   - The ID of the last VM to hibernate

Examples:
  ${0##*/} 400 430

Notes:
  - Requires sufficient disk space for RAM state
  - Hibernation time depends on RAM size
  - Use BulkStart.sh or BulkResume.sh to restore
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

# --- hibernate_vm ------------------------------------------------------------
hibernate_vm() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    # Check if VM is running
    local vm_status
    vm_status=$(qm status "$vmid" --node "$node" 2>/dev/null | awk '{print $2}')
    
    if [[ "$vm_status" != "running" ]]; then
        __update__ "VM ${vmid} is not running (status: ${vm_status}), skipping"
        return 0
    fi
    
    __update__ "Hibernating VM ${vmid} on node ${node}..."
    if qm suspend "$vmid" --todisk 1 --node "$node" 2>/dev/null; then
        __ok__ "VM ${vmid} hibernated successfully on ${node}"
    else
        __err__ "Failed to hibernate VM ${vmid} on ${node}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk hibernate (cluster-wide): VMs ${FIRST_VM_ID} to ${LAST_VM_ID}"
    __warn__ "Hibernation saves RAM to disk and may take time for VMs with large RAM"
    
    # Confirm action
    if ! __prompt_user_yn__ "Hibernate VMs ${FIRST_VM_ID}-${LAST_VM_ID}?"; then
        __info__ "Operation cancelled by user"
        exit 0
    fi
    
    local failed_count=0
    local processed_count=0
    local skipped_count=0
    
    for (( vm_id=FIRST_VM_ID; vm_id<=LAST_VM_ID; vm_id++ )); do
        if hibernate_vm "$vm_id"; then
            ((processed_count++))
        else
            ((failed_count++))
        fi
    done
    
    echo
    __info__ "Operation complete:"
    __info__ "  Processed: ${processed_count}"
    if (( failed_count > 0 )); then
        __warn__ "  Failed: ${failed_count}"
    fi
    
    if (( failed_count > 0 )); then
        __err__ "Hibernation completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "All VMs hibernated successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-16: Created for bulk VM hibernation
