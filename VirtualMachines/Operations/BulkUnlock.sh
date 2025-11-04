#!/bin/bash
#
# BulkUnlock.sh
#
# Unlocks a range of virtual machines (VMs) within a Proxmox VE environment.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   BulkUnlock.sh <first_vm_id> <last_vm_id>
#
# Arguments:
#   first_vm_id - The ID of the first VM to unlock.
#   last_vm_id  - The ID of the last VM to unlock.
#
# Examples:
#   BulkUnlock.sh 400 430
#   This will unlock VMs 400-430 regardless of which nodes they are on
#
# Function Index:
#   - main
#   - unlock_vm_callback
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

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk unlock (cluster-wide): VMs ${START_VMID} to ${END_VMID}"

    # Local callback for bulk operation
    unlock_vm_callback() {
        local vmid="$1"
        __vm_unlock__ "$vmid"
    }

    # Use BulkOperations framework
    __bulk_vm_operation__ --name "Unlock" --report "$START_VMID" "$END_VMID" unlock_vm_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "All VMs unlocked successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and BulkOperations framework
