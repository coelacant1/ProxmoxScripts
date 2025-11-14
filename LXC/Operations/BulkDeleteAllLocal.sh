#!/bin/bash
#
# BulkDeleteAllLocal.sh
#
# Deletes all LXC containers on the local Proxmox node.
# WARNING: This permanently deletes ALL containers on the current node.
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
#   - delete_ct_callback
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

    # Get list of all local container IDs
    local ct_ids
    ct_ids=$(pct list | awk 'NR>1 {print $1}')

    if [[ -z "$ct_ids" ]]; then
        __info__ "No containers found on this Proxmox node"
        exit 0
    fi

    # Convert to array
    local -a ct_array
    read -r -a ct_array <<< "$ct_ids"

    __warn__ "This will permanently delete ${#ct_array[@]} container(s) on this node:"
    echo "$ct_ids"

    # Confirm unless --force
    if [[ -z "${FORCE:-}" ]]; then
        if ! __prompt_user_yn__ "Are you sure you want to delete all containers?"; then
            __info__ "Operation canceled"
            exit 0
        fi
    fi

    # Local callback for bulk operation
    delete_ct_callback() {
        local vmid="$1"

        # Disable protection
        __ct_set_protection__ "$vmid" 0

        # Stop container
        __ct_stop__ "$vmid"

        # Delete container
        __ct_delete__ "$vmid" --purge
    }

    # Process each container
    BULK_OPERATION_NAME="Delete"
    for vmid in "${ct_array[@]}"; do
        if delete_ct_callback "$vmid"; then
            ((BULK_SUCCESS++))
        else
            ((BULK_FAILED++))
            BULK_FAILED_IDS+=("$vmid")
        fi
    done

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "All containers deleted successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and BulkOperations framework
#   - Pending validation
