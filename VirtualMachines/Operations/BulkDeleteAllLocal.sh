#!/bin/bash
#
# BulkDeleteAllLocal.sh
#
# Deletes all virtual machines (VMs) on the local Proxmox node.
# WARNING: This permanently deletes ALL VMs on the current node.
#
# Usage:
#   BulkDeleteAllLocal.sh [--force]
#
# Arguments:
#   --force - Skip confirmation prompt
#
# Examples:
#   BulkDeleteAllLocal.sh
#   BulkDeleteAllLocal.sh --force
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

# Parse arguments
__parse_args__ "--force:flag" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Get list of all local VM IDs
    local vm_ids
    vm_ids=$(qm list | awk 'NR>1 {print $1}')

    if [[ -z "$vm_ids" ]]; then
        __info__ "No VMs found on this Proxmox node"
        exit 0
    fi

    # Convert to array
    local -a vm_array
    read -r -a vm_array <<<"$vm_ids"

    __warn__ "This will permanently delete ${#vm_array[@]} VM(s) on this node:"
    echo "$vm_ids"

    # Safety check: Require --force flag in non-interactive mode
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]] && [[ "${FORCE:-false}" != "true" ]]; then
        __err__ "Destructive operation requires --force flag in non-interactive mode"
        __err__ "Usage: BulkDeleteAllLocal.sh --force"
        __err__ "Or add '--force' to parameters in GUI"
        exit 1
    fi

    # Prompt for confirmation (unless --force provided)
    if [[ "${FORCE:-false}" == "true" ]]; then
        __info__ "Force mode enabled (--force flag) - proceeding without confirmation"
    elif ! __prompt_user_yn__ "Are you sure you want to delete all VMs?"; then
        __info__ "Operation canceled"
        exit 0
    fi

    # Local callback for bulk operation
    delete_vm_callback() {
        local vmid="$1"

        # Disable protection
        __vm_set_protection__ "$vmid" 0

        # Stop VM
        __vm_stop__ "$vmid"

        # Delete VM
        __vm_delete__ "$vmid" --purge
    }

    # Process each VM
    BULK_OPERATION_NAME="Delete"
    for vmid in "${vm_array[@]}"; do
        if delete_vm_callback "$vmid"; then
            ((BULK_SUCCESS += 1))
        else
            ((BULK_FAILED += 1))
            BULK_FAILED_IDS+=("$vmid")
        fi
    done

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "All VMs deleted successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Fixed non-interactive mode detection for destructive operations
# - 2025-11-20: Updated to use ArgumentParser and BulkOperations framework
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# -
#

