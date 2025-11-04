#!/bin/bash
#
# BulkToggleProtectionMode.sh
#
# Enables or disables protection mode for a range of LXC containers.
# Protection mode prevents accidental deletion or modification.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkToggleProtectionMode.sh <start_ct_id> <end_ct_id> <action>
#
# Arguments:
#   start_ct_id - Starting container ID
#   end_ct_id   - Ending container ID
#   action      - "enable" or "disable"
#
# Examples:
#   BulkToggleProtectionMode.sh 400 429 enable
#   BulkToggleProtectionMode.sh 200 209 disable
#
# Function Index:
#   - main
#   - toggle_protection_callback
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
__parse_args__ "start_vmid:vmid end_vmid:vmid action:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Validate action
    if [[ "$ACTION" != "enable" && "$ACTION" != "disable" ]]; then
        __err__ "Invalid action: ${ACTION}. Must be 'enable' or 'disable'."
        exit 1
    fi

    local protection_state=1
    [[ "$ACTION" = "disable" ]] && protection_state=0

    __info__ "Bulk toggle protection mode: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "Action: ${ACTION}"

    toggle_protection_callback() {
        local vmid="$1"
        __ct_set_protection__ "$vmid" "$protection_state"
    }

    __bulk_ct_operation__ --name "Toggle Protection" --report "$START_VMID" "$END_VMID" toggle_protection_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Protection mode updated successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and BulkOperations framework
#   - Pending validation
