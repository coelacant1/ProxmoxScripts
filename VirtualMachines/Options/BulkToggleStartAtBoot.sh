#!/bin/bash
#
# BulkToggleStartAtBoot.sh
#
# Toggles start at boot option for virtual machines within a Proxmox VE cluster.
# Uses BulkOperations framework for cluster-wide execution.
#
# Usage:
#   BulkToggleStartAtBoot.sh <start_vmid> <end_vmid> <enable|disable>
#
# Arguments:
#   start_vmid     - Starting VM ID
#   end_vmid       - Ending VM ID
#   enable|disable - Action to perform
#
# Examples:
#   BulkToggleStartAtBoot.sh 400 430 enable
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
__parse_args__ "start_vmid:vmid end_vmid:vmid action:choice(enable,disable)" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    local onboot_value
    [[ "$ACTION" == "enable" ]] && onboot_value="1" || onboot_value="0"

    toggle_onboot_callback() {
        local vmid="$1"
        __vm_set_config__ "$vmid" --onboot "$onboot_value"
    }

    __bulk_vm_operation__ --name "Toggle Start at Boot (${ACTION})" --report "$START_VMID" "$END_VMID" toggle_onboot_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Start at boot ${ACTION}d successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
#
# Fixes:
# -
#
# Known issues:
# -
#

