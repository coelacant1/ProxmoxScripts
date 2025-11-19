#!/bin/bash
#
# BulkResizeStorage.sh
#
# Resizes storage for a range of virtual machines (VMs) within a Proxmox VE environment.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   BulkResizeStorage.sh <start_vm_id> <end_vm_id> <disk> <size>
#
# Arguments:
#   start_vm_id  - The ID of the first VM to update.
#   end_vm_id    - The ID of the last VM to update.
#   disk         - The disk to resize (e.g., 'scsi0', 'virtio0', 'sata0').
#   size         - The size change (e.g., '+10G' to add 10GB).
#
# Examples:
#   BulkResizeStorage.sh 400 430 scsi0 +10G
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
__parse_args__ "start_vmid:vmid end_vmid:vmid disk:string size:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk resize storage: VMs ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "Resizing ${DISK} by ${SIZE}"

    resize_storage_callback() {
        local vmid="$1"
        __vm_resize_disk__ "$vmid" "$DISK" "$SIZE"
    }

    __bulk_vm_operation__ --name "Resize Storage" --report "$START_VMID" "$END_VMID" resize_storage_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "All storage resizes completed successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and BulkOperations framework
#   - Pending validation
