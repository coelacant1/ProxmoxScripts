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

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

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

    if [[ $# -lt 4 ]]; then
        __err__ "Missing required arguments"
        echo "Usage: $0 <pool> <start_vm> <end_vm> <disk_num>"
        exit 64
    fi

    local pool="$1"
    local start_vm="$2"
    local end_vm="$3"
    local disk_num="$4"

    # Validate numeric inputs
    if ! [[ "$start_vm" =~ ^[0-9]+$ ]] || ! [[ "$end_vm" =~ ^[0-9]+$ ]] || ! [[ "$disk_num" =~ ^[0-9]+$ ]]; then
        __err__ "VM indices and disk number must be numeric"
        exit 1
    fi

    if ((start_vm > end_vm)); then
        __err__ "Start VM index must be <= end VM index"
        exit 1
    fi

    local disk_count=$((end_vm - start_vm + 1))

    __warn__ "DESTRUCTIVE OPERATION: Bulk disk deletion"
    __info__ "Pool: $pool"
    __info__ "VM range: $start_vm to $end_vm ($disk_count VMs)"
    __info__ "Disk number: $disk_num"

    if ! __prompt_yes_no__ "Delete $disk_count disk(s) from pool $pool?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    __info__ "Starting bulk disk deletion"

    local deleted=0
    local failed=0

    for vm_index in $(seq "$start_vm" "$end_vm"); do
        local disk_name="vm-${vm_index}-disk-${disk_num}"

        if delete_disk "$pool" "$disk_name"; then
            ((deleted++))
        else
            ((failed++))
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

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
