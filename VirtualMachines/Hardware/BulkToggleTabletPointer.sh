#!/bin/bash
#
# BulkToggleTabletPointer.sh
#
# Toggles tablet/pointer device for virtual machines within a Proxmox VE cluster.
# Tablet device provides absolute mouse positioning in VMs.
#
# Usage:
#   BulkToggleTabletPointer.sh <start_vmid> <end_vmid> <enable|disable>
#
# Arguments:
#   start_vmid     - Starting VM ID
#   end_vmid       - Ending VM ID
#   enable|disable - Action to perform
#
# Examples:
#   BulkToggleTabletPointer.sh 400 430 disable
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
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid action:choice(enable,disable,1,0)" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    local tablet_value
    case "$ACTION" in
        enable | 1) tablet_value="1" ;;
        disable | 0) tablet_value="0" ;;
    esac

    __warn__ "VMs must be restarted for changes to take effect"

    toggle_tablet_callback() {
        local vmid="$1"
        __vm_set_config__ "$vmid" --tablet "$tablet_value"
    }

    __bulk_vm_operation__ --name "Toggle Tablet (${ACTION})" --report "$START_VMID" "$END_VMID" toggle_tablet_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Tablet setting updated successfully!"
}

main

# Testing status:
#   - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
