#!/bin/bash
#
# DiskDeleteWithSnapshot.sh
#
# Deletes Ceph disk image after removing __base__ snapshot if it's the only one.
#
# Usage:
#   DiskDeleteWithSnapshot.sh <pool> <disk>
#
# Arguments:
#   pool - Ceph pool name
#   disk - Disk image name
#
# Examples:
#   DiskDeleteWithSnapshot.sh mypool my-disk
#   DiskDeleteWithSnapshot.sh ceph-pool vm-100-disk-0
#
# Function Index:
#   - delete_snapshot_and_disk
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "pool:string disk:string" "$@"

# --- delete_snapshot_and_disk ------------------------------------------------
delete_snapshot_and_disk() {
    local pool="$1"
    local disk="$2"

    __info__ "Checking snapshots for: $pool/$disk"

    local snapshot_list
    if ! snapshot_list=$(rbd snap ls "${pool}/${disk}" 2>&1); then
        __err__ "Failed to list snapshots"
        return 1
    fi

    echo "$snapshot_list"

    # Count snapshots (excluding header)
    local total_snapshots
    total_snapshots=$(echo "${snapshot_list}" | grep -v "NAME" | wc -l)

    __info__ "Total snapshots: $total_snapshots"

    # Check if __base__ is the only snapshot
    if echo "${snapshot_list}" | grep -q "__base__" && [[ "${total_snapshots}" -eq 1 ]]; then
        __info__ "Only __base__ snapshot found - proceeding with deletion"

        # Unprotect snapshot
        __update__ "Unprotecting snapshot: ${pool}/${disk}@__base__"
        if ! rbd snap unprotect "${pool}/${disk}@__base__" 2>&1; then
            __err__ "Failed to unprotect snapshot"
            return 1
        fi
        __ok__ "Snapshot unprotected"

        # Delete snapshot
        __update__ "Deleting snapshot: ${pool}/${disk}@__base__"
        if ! rbd snap rm "${pool}/${disk}@__base__" 2>&1; then
            __err__ "Failed to delete snapshot"
            return 1
        fi
        __ok__ "Snapshot deleted"

        # Remove disk
        __update__ "Deleting disk: ${pool}/${disk}"
        if ! rbd rm "${disk}" -p "${pool}" 2>&1; then
            __err__ "Failed to delete disk"
            return 1
        fi
        __ok__ "Disk deleted"

        return 0
    else
        __warn__ "Multiple snapshots exist or __base__ not found"
        __info__ "No action taken - manual intervention required"
        return 2
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __warn__ "DESTRUCTIVE OPERATION: Snapshot and disk deletion"
    __info__ "Pool: $POOL"
    __info__ "Disk: $DISK"

    if ! __prompt_user_yn__ "Delete disk $DISK from pool $POOL?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    if delete_snapshot_and_disk "$POOL" "$DISK"; then
        echo
        __ok__ "Snapshot and disk deleted successfully!"
    else
        local exit_code=$?
        echo
        if [[ $exit_code -eq 2 ]]; then
            __warn__ "Deletion skipped - check snapshot status"
            exit 0
        else
            __err__ "Deletion failed"
            exit 1
        fi
    fi
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: Pending validation
# - 2025-11-20: Updated to use ArgumentParser.sh
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# - Pending validation
# -
#

