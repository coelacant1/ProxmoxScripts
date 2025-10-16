#!/bin/bash
#
# BulkSuspend.sh
#
# Suspends (pauses) a range of virtual machines (VMs) within a Proxmox VE environment.
# Suspend pauses VM execution by saving RAM state to memory, not disk.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkSuspend.sh <first_vm_id> <last_vm_id>
#
# Arguments:
#   first_vm_id - The ID of the first VM to suspend.
#   last_vm_id  - The ID of the last VM to suspend.
#
# Examples:
#   ./BulkSuspend.sh 400 430
#   This will suspend VMs 400-430 regardless of which nodes they are on
#
# Notes:
#   - Suspend keeps RAM in memory (faster than hibernate)
#   - VM state is lost if host reboots or loses power
#   - Use BulkResume.sh to resume suspended VMs
#   - For persistent state, use BulkHibernate.sh instead
#
# Function Index:
#   - usage
#   - parse_args
#   - suspend_vm
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

Suspends (pauses) a range of VMs across the entire cluster.
Keeps RAM state in memory for instant resume.
Automatically detects which node each VM is on.

Arguments:
  first_vm_id  - The ID of the first VM to suspend
  last_vm_id   - The ID of the last VM to suspend

Examples:
  ${0##*/} 400 430

Notes:
  - Suspend is instant (RAM stays in memory)
  - State lost on host reboot/power loss
  - Use BulkResume.sh to resume
  - For persistent state, use BulkHibernate.sh
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

# --- suspend_vm --------------------------------------------------------------
suspend_vm() {
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
    
    __update__ "Suspending VM ${vmid} on node ${node}..."
    if qm suspend "$vmid" --node "$node" 2>/dev/null; then
        __ok__ "VM ${vmid} suspended successfully on ${node}"
    else
        __err__ "Failed to suspend VM ${vmid} on ${node}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk suspend (cluster-wide): VMs ${FIRST_VM_ID} to ${LAST_VM_ID}"
    __warn__ "Suspended VMs keep RAM in memory - state lost on host reboot"
    
    # Confirm action
    if ! __prompt_user_yn__ "Suspend VMs ${FIRST_VM_ID}-${LAST_VM_ID}?"; then
        __info__ "Operation cancelled by user"
        exit 0
    fi
    
    local failed_count=0
    local processed_count=0
    local skipped_count=0
    
    for (( vm_id=FIRST_VM_ID; vm_id<=LAST_VM_ID; vm_id++ )); do
        if suspend_vm "$vm_id"; then
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
        __err__ "Suspend completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "All VMs suspended successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-16: Created for bulk VM suspension
