#!/bin/bash
#
# DiskDeleteBulk.sh
#
# Deletes multiple VM disk images from Ceph storage pool.
#
# Usage:
#   DiskDeleteBulk.sh <pool> <start_vm> <end_vm> <disk_num>
#
# Arguments:
#   pool - Ceph pool name
#   start_vm - Starting VM index
#   end_vm - Ending VM index
#   disk_num - Disk number
#
# Examples:
#   DiskDeleteBulk.sh vm_pool 1 100 1
#   DiskDeleteBulk.sh ceph_pool 200 250 0
#
# Function Index:
#   - delete_disk
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

__parse_args__ "pool:string start_vm:number end_vm:number disk_num:number" "$@"

# Validate range
if ((START_VM > END_VM)); then
    __err__ "Start VM index must be <= end VM index"
    exit 64
fi

# --- delete_disk -------------------------------------------------------------
delete_disk() {
    local pool="$1"
    local disk="$2"

    if rbd rm "$disk" -p "$pool" 2>&1; then
        __ok__ "Deleted: $disk"
        return 0
    else
        __warn__ "Failed to delete: $disk"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    local disk_count=$((END_VM - START_VM + 1))

    __warn__ "DESTRUCTIVE OPERATION: Bulk disk deletion"
    __info__ "Pool: $POOL"
    __info__ "VM range: $START_VM to $END_VM ($disk_count VMs)"
    __info__ "Disk number: $DISK_NUM"

    if ! __prompt_user_yn__ "Delete $disk_count disk(s) from pool $POOL?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    __info__ "Starting bulk disk deletion"

    local deleted=0
    local failed=0

    for vm_index in $(seq "$START_VM" "$END_VM"); do
        local disk_name="vm-${vm_index}-disk-${DISK_NUM}"

        if delete_disk "$POOL" "$disk_name"; then
            deleted=$((deleted + 1))
        else
            failed=$((failed + 1))
        fi
    done

    echo
    __info__ "Bulk Deletion Summary:"
    __info__ "  Deleted: $deleted"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: $failed" || __info__ "  Failed: $failed"

    [[ $failed -gt 0 ]] && exit 1
    __ok__ "Bulk disk deletion completed!"
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Fixed arithmetic increment syntax (CONTRIBUTING.md Section 3.7)
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: Updated to use ArgumentParser.sh
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-24: Changed ((var += 1)) to var=$((var + 1)) for set -e compatibility
#
# Known issues:
# -
#

