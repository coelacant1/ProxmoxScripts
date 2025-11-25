#!/bin/bash
#
# BulkStop.sh
#
# Stops virtual machines within a Proxmox VE cluster.
# Uses BulkOperations framework for cluster-wide execution.
#
# Usage:
#   BulkStop.sh <start_vmid> <end_vmid>
#
# Arguments:
#   start_vmid - Starting VM ID
#   end_vmid   - Ending VM ID
#
# Examples:
#   BulkStop.sh 400 430
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
__parse_args__ "start_vmid:vmid end_vmid:vmid" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    stop_callback() {
        local vmid="$1"
        __vm_stop__ "$vmid"
    }

    __bulk_vm_operation__ --name "Stop VMs" --report "$START_VMID" "$END_VMID" stop_callback

    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Stop completed successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
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

