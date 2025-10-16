#!/bin/bash
#
# BulkResume.sh
#
# Resumes a range of suspended or hibernated virtual machines (VMs) within a Proxmox VE environment.
# Works with both suspended (paused) and hibernated VMs.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkResume.sh <first_vm_id> <last_vm_id>
#
# Arguments:
#   first_vm_id - The ID of the first VM to resume.
#   last_vm_id  - The ID of the last VM to resume.
#
# Examples:
#   ./BulkResume.sh 400 430
#   This will resume VMs 400-430 regardless of which nodes they are on
#
# Notes:
#   - Works with both suspended (paused) and hibernated VMs
#   - Suspended VMs resume instantly from memory
#   - Hibernated VMs resume by loading state from disk
#   - Running VMs are skipped automatically
#
# Function Index:
#   - usage
#   - parse_args
#   - resume_vm
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

Resumes suspended or hibernated VMs across the entire cluster.
Automatically detects which node each VM is on.

Arguments:
  first_vm_id  - The ID of the first VM to resume
  last_vm_id   - The ID of the last VM to resume

Examples:
  ${0##*/} 400 430

Notes:
  - Works with both suspended and hibernated VMs
  - Suspended VMs resume instantly from memory
  - Hibernated VMs resume by loading from disk
  - Running VMs are skipped
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

# --- resume_vm ---------------------------------------------------------------
resume_vm() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    # Check VM status
    local vm_status
    vm_status=$(qm status "$vmid" --node "$node" 2>/dev/null | awk '{print $2}')
    
    case "$vm_status" in
        running)
            __update__ "VM ${vmid} is already running, skipping"
            return 0
            ;;
        paused|suspended)
            __update__ "Resuming suspended VM ${vmid} on node ${node}..."
            ;;
        stopped)
            # Check if it's hibernated by looking for vmstate disk
            local has_vmstate
            has_vmstate=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -c "vmstate:" || true)
            if [[ "$has_vmstate" -gt 0 ]]; then
                __update__ "Resuming hibernated VM ${vmid} on node ${node}..."
            else
                __update__ "VM ${vmid} is stopped (not suspended/hibernated), skipping"
                return 0
            fi
            ;;
        *)
            __update__ "VM ${vmid} has status '${vm_status}', skipping"
            return 0
            ;;
    esac
    
    if qm resume "$vmid" --node "$node" 2>/dev/null; then
        __ok__ "VM ${vmid} resumed successfully on ${node}"
    else
        __err__ "Failed to resume VM ${vmid} on ${node}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk resume (cluster-wide): VMs ${FIRST_VM_ID} to ${LAST_VM_ID}"
    __info__ "Will resume both suspended and hibernated VMs"
    
    # Confirm action
    if ! __prompt_user_yn__ "Resume VMs ${FIRST_VM_ID}-${LAST_VM_ID}?"; then
        __info__ "Operation cancelled by user"
        exit 0
    fi
    
    local failed_count=0
    local processed_count=0
    local skipped_count=0
    
    for (( vm_id=FIRST_VM_ID; vm_id<=LAST_VM_ID; vm_id++ )); do
        if resume_vm "$vm_id"; then
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
        __err__ "Resume completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "All VMs resumed successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-16: Created for bulk VM resume
