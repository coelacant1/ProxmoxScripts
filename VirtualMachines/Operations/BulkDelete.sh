#!/bin/bash
#
# BulkDelete.sh
#
# Deletes virtual machines (VMs) within a Proxmox VE cluster by unprotecting, stopping,
# and destroying them. Uses the BulkOperations framework for proper cluster-wide execution
# with progress tracking and error handling.
#
# WARNING: This script permanently deletes VMs. Use with extreme caution!
#
# Usage:
#   BulkDelete.sh <first_vm_id> <last_vm_id> [--yes]
#
# Arguments:
#   first_vm_id - The ID of the first VM to delete.
#   last_vm_id  - The ID of the last VM to delete.
#   --yes       - Skip confirmation prompt (optional).
#
# Examples:
#   BulkDelete.sh 600 650
#   BulkDelete.sh 600 650 --yes
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments using declarative API
__parse_args__ "first_vm_id:vmid last_vm_id:vmid --yes:flag" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __warn__ "DESTRUCTIVE: This will permanently delete VMs ${FIRST_VM_ID} to ${LAST_VM_ID}"
    __warn__ "This operation cannot be undone!"

    # Safety check: Require --yes flag in non-interactive mode
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]] && [[ "$YES" != "true" ]]; then
        __err__ "Destructive operation requires --yes flag in non-interactive mode"
        __err__ "Usage: BulkDelete.sh $FIRST_VM_ID $LAST_VM_ID --yes"
        __err__ "Or add '--yes' to parameters in GUI"
        exit 1
    fi

    # Prompt for confirmation (unless --yes flag provided)
    if [[ "$YES" == "true" ]]; then
        __info__ "Auto-confirm enabled (--yes flag) - proceeding without prompt"
    elif ! __prompt_user_yn__ "Are you absolutely sure you want to delete these VMs?"; then
        __info__ "Deletion cancelled by user"
        exit 0
    fi

    # Define deletion logic as local callback for BulkOperations
    delete_vm_callback() {
        local vmid="$1"

        # Stop if running (qm stop is forceful by default)
        if __vm_is_running__ "$vmid"; then
            if __vm_stop__ "$vmid"; then
                # Stop command succeeded, wait for VM to reach stopped state
                __vm_wait_for_status__ "$vmid" "stopped" --timeout 30 2>/dev/null || {
                    # Timeout waiting for stopped status - skip this VM
                    echo "Error: VM $vmid did not stop within timeout" >&2
                    return 1
                }
            else
                # Stop command failed immediately - skip this VM
                echo "Error: Failed to issue stop command for VM $vmid" >&2
                return 1
            fi
        fi

        # Destroy VM using remote execution utility
        __vm_node_exec__ "$vmid" "qm destroy {vmid} --skiplock --purge" 2>/dev/null
    }

    # Use BulkOperations framework
    __bulk_vm_operation__ \
        --name "Delete VMs" \
        --report \
        "$FIRST_VM_ID" \
        "$LAST_VM_ID" \
        delete_vm_callback

    local result=$?

    # Exit with appropriate status
    if ((result != 0)); then
        exit 1
    fi
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2026-01-08
#
# Changes:
# - 2026-01-08: Removed --protection 0 call (unprotection must be handled by Options/BulkToggleProtectionMode.sh)
# - 2026-01-08: Improved stop command error handling with better timeout and error messages
# - 2025-10-14: Converted to cluster-wide with safety features
# - 2025-10-27: Updated to follow contributing guide with proper BulkOperations framework usage
#
# Fixes:
# -
#
# Known issues:
# -
#

