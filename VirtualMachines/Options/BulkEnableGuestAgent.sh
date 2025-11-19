#!/bin/bash
#
# BulkEnableGuestAgent.sh
#
# Enables QEMU guest agent for virtual machines within a Proxmox VE cluster.
# Optionally restarts VMs after enabling to apply changes.
#
# Usage:
#   BulkEnableGuestAgent.sh <start_vmid> <end_vmid> [--restart]
#
# Arguments:
#   start_vmid - Starting VM ID
#   end_vmid   - Ending VM ID
#   --restart  - Optional flag to restart VMs after enabling
#
# Examples:
#   BulkEnableGuestAgent.sh 400 430
#   BulkEnableGuestAgent.sh 400 430 --restart
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
__parse_args__ "start_vmid:vmid end_vmid:vmid --restart:flag" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    enable_agent_callback() {
        local vmid="$1"

        __vm_set_config__ "$vmid" --agent "enabled=1"

        if [[ "$RESTART" == "true" ]]; then
            if __vm_is_running__ "$vmid"; then
                __vm_reset__ "$vmid"
            fi
        fi
    }

    __bulk_vm_operation__ --name "Enable Guest Agent" --report "$START_VMID" "$END_VMID" enable_agent_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Guest agent enabled successfully!"
}

main

# Testing status:
#   - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
