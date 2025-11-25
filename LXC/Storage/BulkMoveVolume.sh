#!/bin/bash
#
# BulkMoveVolume.sh
#
# Moves a specified volume (e.g., rootfs, mp0) for a range of LXC containers to new storage.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkMoveVolume.sh <start_ct_id> <end_ct_id> <volume> <target_storage>
#
# Arguments:
#   start_ct_id     - Starting container ID
#   end_ct_id       - Ending container ID
#   volume          - Volume identifier (e.g., 'rootfs', 'mp0')
#   target_storage  - Target storage name (e.g., 'local-zfs')
#
# Examples:
#   BulkMoveVolume.sh 100 105 rootfs local-zfs
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
__parse_args__ "start_vmid:vmid end_vmid:vmid volume:string target_storage:storage" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk move volume: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "Volume: ${VOLUME} -> Storage: ${TARGET_STORAGE}"

    move_volume_callback() {
        local vmid="$1"
        __ct_move_volume__ "$vmid" "$VOLUME" "$TARGET_STORAGE"
    }

    __bulk_ct_operation__ --name "Move Volume" --report "$START_VMID" "$END_VMID" move_volume_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Volumes moved successfully!"
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
# - 2025-11-20: Validated against PVE Guide v9.1-1 (Section 22.11) and CONTRIBUTING.md
#
# Fixes:
# - Fixed ArgumentParser types (vmid, storage)
#
# Known issues:
# - Pending validation
# -
#

