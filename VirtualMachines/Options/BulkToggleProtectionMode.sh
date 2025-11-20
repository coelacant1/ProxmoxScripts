#!/bin/bash
#
# BulkToggleProtectionMode.sh
#
# Toggles protection mode for virtual machines within a Proxmox VE cluster.
# Uses BulkOperations framework for cluster-wide execution.
#
# Usage:
#   BulkToggleProtectionMode.sh <start_vmid> <end_vmid> <enable|disable>
#
# Arguments:
#   start_vmid     - Starting VM ID
#   end_vmid       - Ending VM ID
#   enable|disable - Action to perform
#
# Examples:
#   BulkToggleProtectionMode.sh 400 430 enable
#   BulkToggleProtectionMode.sh 400 430 disable
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

    local protection_value
    [[ "$ACTION" == "enable" ]] && protection_value="1" || protection_value="0"

    toggle_protection_callback() {
        local vmid="$1"
        __vm_set_config__ "$vmid" --protection "$protection_value"
    }

    __bulk_vm_operation__ --name "Toggle Protection (${ACTION})" --report "$START_VMID" "$END_VMID" toggle_protection_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Protection ${ACTION}d successfully!"
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

