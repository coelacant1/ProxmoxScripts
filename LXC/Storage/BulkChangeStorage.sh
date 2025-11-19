#!/bin/bash
#
# BulkChangeStorage.sh
#
# Updates storage configuration in LXC container config files.
# Changes storage identifiers (e.g., local-lvm to local-zfs).
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkChangeStorage.sh <start_ct_id> <end_ct_id> <current_storage> <new_storage>
#
# Arguments:
#   start_ct_id      - Starting container ID
#   end_ct_id        - Ending container ID
#   current_storage  - Current storage identifier (e.g., 'local-lvm')
#   new_storage      - New storage identifier (e.g., 'local-zfs')
#
# Examples:
#   BulkChangeStorage.sh 100 105 local-lvm local-zfs
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
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:int end_vmid:int current_storage:string new_storage:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk change storage: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "From: ${CURRENT_STORAGE} -> To: ${NEW_STORAGE}"

    change_storage_callback() {
        local vmid="$1"
        __ct_change_storage__ "$vmid" "$CURRENT_STORAGE" "$NEW_STORAGE"
    }

    __bulk_ct_operation__ --name "Change Storage" --report "$START_VMID" "$END_VMID" change_storage_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Storage configuration updated successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and BulkOperations framework
#   - Pending validation
