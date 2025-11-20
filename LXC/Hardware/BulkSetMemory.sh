#!/bin/bash
#
# BulkSetMemory.sh
#
# Sets the memory (RAM) and optional swap allocation for a range of LXC containers.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkSetMemory.sh <start_ct_id> <end_ct_id> <memory_MB> [swap_MB]
#
# Arguments:
#   start_ct_id - The ID of the first container to update.
#   end_ct_id   - The ID of the last container to update.
#   memory_MB   - Memory allocation in MB.
#   swap_MB     - Optional. Swap allocation in MB (default: 0).
#
# Examples:
#   BulkSetMemory.sh 400 402 2048
#   BulkSetMemory.sh 400 402 2048 1024
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
# shellcheck source=Utilities/BulkOperations.sh
source "${UTILITYPATH}/BulkOperations.sh"
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid memory_mb:memory swap_mb:memory:0" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk set memory config: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "Memory: ${MEMORY_MB} MB, Swap: ${SWAP_MB} MB"

    # Local callback for bulk operation
    set_memory_callback() {
        local vmid="$1"
        __ct_set_memory__ "$vmid" "$MEMORY_MB" "$SWAP_MB"
    }

    # Use BulkOperations framework
    __bulk_ct_operation__ --name "Set Memory" --report "$START_VMID" "$END_VMID" set_memory_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Memory configuration updated successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use ArgumentParser and BulkOperations framework
# - 2025-11-20: Pending validation
# - 2025-11-20: Validated against PVE Guide Chapter 11, Section 22.11
#
# Fixes:
# -
#
# Known issues:
# - Pending validation
# -
#

