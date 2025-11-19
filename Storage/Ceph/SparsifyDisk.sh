#!/bin/bash
#
# SparsifyDisk.sh
#
# Sparsifies (compacts) all RBD disks associated with a VM in a Ceph storage pool.
# Zeroed blocks are reclaimed, making space available for reuse.
#
# Usage:
#   SparsifyDisk.sh <pool_name> <vm_id>
#
# Arguments:
#   pool_name - Name of the Ceph storage pool
#   vm_id     - VM ID whose disks will be sparsified
#
# Examples:
#   SparsifyDisk.sh mypool 101
#
# Notes:
#   - Assumes RBD image naming: vm-<vm_id>-disk-<X>
#   - Zero out unused space in VM first (sdelete -z on Windows, fstrim on Linux)
#   - Requires permissions to run 'rbd sparsify'
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

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "pool_name:string vm_id:vmid" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __update__ "Querying RBD disks for VM $VM_ID in pool '$POOL_NAME'"

    local images
    images=$(rbd ls "$POOL_NAME" | grep "vm-${VM_ID}-disk-" || true)

    if [[ -z "$images" ]]; then
        __info__ "No disks found for VM $VM_ID in pool '$POOL_NAME'"
        exit 0
    fi

    __info__ "Found disk(s): $images"

    local success=0
    local failed=0

    while IFS= read -r image_name; do
        [[ -z "$image_name" ]] && continue

        __update__ "Sparsifying ${POOL_NAME}/${image_name}"
        if rbd sparsify "${POOL_NAME}/${image_name}" &>/dev/null; then
            __ok__ "Sparsified ${image_name}"
            ((success += 1))
        else
            __warn__ "Failed to sparsify ${image_name}"
            ((failed += 1))
        fi
    done <<<"$images"

    __info__ "Success: $success, Failed: $failed"
    [[ $failed -gt 0 ]] && exit 1
    __ok__ "Disk sparsification complete for VM $VM_ID"
}

main

# Testing status:
#   - Pending validation
