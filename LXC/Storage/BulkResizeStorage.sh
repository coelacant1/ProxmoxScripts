#!/bin/bash
#
# BulkResizeStorage.sh
#
# Resizes a specified disk (e.g., rootfs) for a range of LXC containers.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkResizeStorage.sh <start_ct_id> <end_ct_id> <disk_id> <new_size>
#
# Arguments:
#   start_ct_id - Starting container ID
#   end_ct_id   - Ending container ID
#   disk_id     - Disk identifier (e.g., 'rootfs', 'mp0')
#   new_size    - New size or increment (e.g., '20G', '+5G')
#
# Examples:
#   BulkResizeStorage.sh 100 105 rootfs 20G
#   BulkResizeStorage.sh 100 105 rootfs +5G
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
__parse_args__ "start_vmid:int end_vmid:int disk_id:string new_size:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk resize storage: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "Disk: ${DISK_ID}, New size: ${NEW_SIZE}"

    resize_storage_callback() {
        local vmid="$1"
        __ct_resize_disk__ "$vmid" "$DISK_ID" "$NEW_SIZE"
    }

    __bulk_ct_operation__ --name "Resize Storage" --report "$START_VMID" "$END_VMID" resize_storage_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Storage resized successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and BulkOperations framework
#   - Pending validation
