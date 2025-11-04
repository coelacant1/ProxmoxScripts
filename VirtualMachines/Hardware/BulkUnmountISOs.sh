#!/bin/bash
#
# BulkUnmountISOs.sh
#
# Unmounts ISO images from CD/DVD drives for virtual machines within a Proxmox VE cluster.
# Uses BulkOperations framework for cluster-wide execution.
#
# Usage:
#   BulkUnmountISOs.sh <start_vmid> <end_vmid>
#
# Arguments:
#   start_vmid - Starting VM ID
#   end_vmid   - Ending VM ID
#
# Examples:
#   BulkUnmountISOs.sh 400 430
#
# Function Index:
#   - main
#   - unmount_iso_callback
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
__parse_args__ "start_vmid:vmid end_vmid:vmid" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    unmount_iso_callback() {
        local vmid="$1"

        # Unmount from common CD/DVD drive types
        for drive in ide2 sata0 scsi0; do
            __vm_set_config__ "$vmid" --${drive} "none,media=cdrom" 2>/dev/null || true
        done
    }

    __bulk_vm_operation__ --name "Unmount ISOs" --report "$START_VMID" "$END_VMID" unmount_iso_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "ISOs unmounted successfully!"
}

main

# Testing status:
#   - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
