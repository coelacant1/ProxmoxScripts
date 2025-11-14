#!/bin/bash
#
# BulkSuspend.sh
#
# Suspends (pauses) virtual machines within a Proxmox VE cluster.
# Suspend keeps RAM in memory for instant resume but state is lost on reboot.
# Uses BulkOperations framework for cluster-wide execution.
#
# Usage:
#   BulkSuspend.sh <start_vmid> <end_vmid>
#
# Arguments:
#   start_vmid - Starting VM ID
#   end_vmid   - Ending VM ID
#
# Examples:
#   BulkSuspend.sh 400 430
#
# Function Index:
#   - main
#   - suspend_callback
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
__parse_args__ "start_vmid:vmid end_vmid:vmid" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __warn__ "Suspended VMs keep RAM in memory - state lost on host reboot"

    if ! __prompt_user_yn__ "Suspend VMs ${START_VMID}-${END_VMID}?"; then
        __info__ "Operation cancelled by user"
        exit 0
    fi

    suspend_callback() {
        local vmid="$1"

        if ! __vm_is_running__ "$vmid"; then
            return 2  # Skip non-running VMs
        fi

        __vm_suspend__ "$vmid"
    }

    __bulk_vm_operation__ --name "Suspend VMs" --report "$START_VMID" "$END_VMID" suspend_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Suspend completed successfully!"
}

main

# Testing status:
#   - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
