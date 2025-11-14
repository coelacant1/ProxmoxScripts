#!/bin/bash
#
# BulkHibernate.sh
#
# Hibernates virtual machines within a Proxmox VE cluster by saving RAM state to disk.
# Uses BulkOperations framework for cluster-wide execution with progress tracking.
#
# Usage:
#   BulkHibernate.sh <start_vmid> <end_vmid>
#
# Arguments:
#   start_vmid - Starting VM ID
#   end_vmid   - Ending VM ID
#
# Examples:
#   BulkHibernate.sh 400 430
#
# Function Index:
#   - main
#   - hibernate_callback
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

    __warn__ "Hibernation saves RAM to disk and may take time for VMs with large RAM"

    if ! __prompt_user_yn__ "Hibernate VMs ${START_VMID}-${END_VMID}?"; then
        __info__ "Operation cancelled by user"
        exit 0
    fi

    # Local callback for hibernation operation
    hibernate_callback() {
        local vmid="$1"

        if ! __vm_is_running__ "$vmid"; then
            return 2  # Skip non-running VMs
        fi

        __vm_suspend__ "$vmid" --todisk
    }

    # Use BulkOperations framework
    __bulk_vm_operation__ --name "Hibernate VMs" --report "$START_VMID" "$END_VMID" hibernate_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Hibernation completed successfully!"
}

main

# Testing status:
#   - 2025-10-28: Updated to follow contributing guidelines with BulkOperations framework
