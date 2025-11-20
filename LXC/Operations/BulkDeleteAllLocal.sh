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
    read -r -a ct_array <<<"$ct_ids"

    __warn__ "This will permanently delete ${#ct_array[@]} container(s) on this node:"
    echo "$ct_ids"

    # Safety check: Require --force in non-interactive mode
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]] && [[ "${FORCE}" != "true" ]]; then
        __err__ "Destructive operation requires --force flag in non-interactive mode"
        __err__ "Usage: BulkDeleteAllLocal.sh --force"
        __err__ "Or add '--force' to parameters in GUI"
        exit 1
    fi

    # Prompt for confirmation (unless --force provided)
    if [[ "${FORCE}" == "true" ]]; then
        __info__ "Force mode enabled - proceeding without confirmation"
    elif ! __prompt_user_yn__ "Are you sure you want to delete all containers?"; then
        __info__ "Operation canceled"
        exit 0
    fi

    # Local callback for deletion
    delete_ct_callback() {
        local vmid="$1"

        # Disable protection
        __ct_set_protection__ "$vmid" 0

        # Stop container if running
        if __ct_is_running__ "$vmid"; then
            __ct_stop__ "$vmid" --force 2>/dev/null || true
        fi

        # Delete container with purge
        __ct_node_exec__ "$vmid" "pct destroy {ctid} --purge"
    }

    # Track results
    local success=0
    local failed=0

    # Process each container
    for vmid in "${ct_array[@]}"; do
        __update__ "Deleting container ${vmid}..."
        if delete_ct_callback "$vmid"; then
            success=$((success + 1))
        else
            __warn__ "Failed to delete container ${vmid}"
            failed=$((failed + 1))
        fi
    done

    # Display summary
    echo ""
    __info__ "Deletion Summary:"
    __info__ "  Total: ${#ct_array[@]}"
    __info__ "  Success: ${success}"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: ${failed}" || __info__ "  Failed: ${failed}"

    if [[ $failed -gt 0 ]]; then
        __err__ "Some deletions failed"
        exit 1
    fi

    __ok__ "All containers deleted successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Pending validation
# - 2025-11-20: Updated to use ArgumentParser and BulkOperations framework
# - 2025-11-20: Validated against CONTRIBUTING.md and PVE Guide Chapter 11
# - Added proper non-interactive mode handling
# - Simplified loop logic (doesn't use BulkOperations framework as it processes local-only containers)
#
# Fixes:
# - Fixed --force flag safety check per Section 3.11
#
# Known issues:
# - Pending validation
# -
#

