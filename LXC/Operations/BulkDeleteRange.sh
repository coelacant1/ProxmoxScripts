#!/bin/bash
#
# BulkDeleteRange.sh
#
# Deletes LXC containers within a Proxmox VE cluster by stopping and destroying them.
# Uses BulkOperations framework for cluster-wide execution.
#
# Usage:
#   BulkDeleteRange.sh <start_ctid> <end_ctid> [--yes]
#
# Arguments:
#   start_ctid - Starting container ID
#   end_ctid   - Ending container ID
#   --yes      - Skip confirmation prompt
#
# Examples:
#   BulkDeleteRange.sh 200 210
#   BulkDeleteRange.sh 200 210 --yes
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
# shellcheck source=Utilities/ProxmoxAPI.sh
source "${UTILITYPATH}/ProxmoxAPI.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_ctid:ctid end_ctid:ctid --yes:flag" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __warn__ "WARNING: This will permanently delete containers ${START_CTID} to ${END_CTID}"

    if [[ "$YES" != "true" ]]; then
        if ! __prompt_user_yn__ "Are you absolutely sure you want to delete these containers?"; then
            __info__ "Deletion cancelled by user"
            exit 0
        fi
    fi

    delete_ct_callback() {
        local ctid="$1"

        if __ct_is_running__ "$ctid"; then
            __ct_stop__ "$ctid" --force 2>/dev/null || true
        fi

        __ct_node_exec__ "$ctid" "pct destroy {ctid}"
    }

    __bulk_ct_operation__ --name "Delete Containers" --report "$START_CTID" "$END_CTID" delete_ct_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Deletion completed successfully!"
}

main

# Testing status:
#   - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
