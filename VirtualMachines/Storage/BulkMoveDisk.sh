#!/bin/bash
#
# BulkMoveDisk.sh
#
# Moves VM disks to different storage within a Proxmox VE cluster.
# Uses BulkOperations framework for cluster-wide execution.
#
# Usage:
#   BulkMoveDisk.sh <start_vmid> <end_vmid> <disk> <target_storage>
#
# Arguments:
#   start_vmid      - Starting VM ID
#   end_vmid        - Ending VM ID
#   disk            - Disk identifier (e.g., scsi0, virtio0, sata0)
#   target_storage  - Target storage identifier
#
# Examples:
#   BulkMoveDisk.sh 100 110 scsi0 local-lvm
#
# Function Index:
#   - main
#   - move_disk_callback
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
__parse_args__ "start_vmid:vmid end_vmid:vmid disk:string target_storage:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Moving ${DISK} to storage: ${TARGET_STORAGE}"

    move_disk_callback() {
        local vmid="$1"
        __vm_node_exec__ "$vmid" "qm move-disk {vmid} ${DISK} ${TARGET_STORAGE} --delete 1"
    }

    __bulk_vm_operation__ --name "Move Disk" --report "$START_VMID" "$END_VMID" move_disk_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Disk move completed successfully!"
}

main

# Testing status:
#   - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
