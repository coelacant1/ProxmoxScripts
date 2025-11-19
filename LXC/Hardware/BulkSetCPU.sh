#!/bin/bash
#
# BulkSetCPU.sh
#
# Sets the CPU configuration (cores and sockets) for a range of LXC containers.
# Automatically detects which node each container is on and executes the operation cluster-wide.
#
# Usage:
#   BulkSetCPU.sh <start_ct_id> <end_ct_id> <core_count> [sockets]
#
# Arguments:
#   start_ct_id - The ID of the first container to update.
#   end_ct_id   - The ID of the last container to update.
#   core_count  - Number of CPU cores to assign.
#   sockets     - Optional. Number of CPU sockets (default: 1).
#
# Examples:
#   BulkSetCPU.sh 400 402 4
#   BulkSetCPU.sh 400 402 4 2
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
__parse_args__ "start_vmid:int end_vmid:int core_count:int sockets:int:?" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Set default socket count
    SOCKETS="${SOCKETS:-1}"

    __info__ "Bulk set CPU config: Containers ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "Cores: ${CORE_COUNT}, Sockets: ${SOCKETS}"

    # Local callback for bulk operation
    set_cpu_callback() {
        local vmid="$1"
        __ct_set_cpu__ "$vmid" "$CORE_COUNT" "$SOCKETS"
    }

    # Use BulkOperations framework
    __bulk_ct_operation__ --name "Set CPU" --report "$START_VMID" "$END_VMID" set_cpu_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "CPU configuration updated successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and BulkOperations framework
#   - Pending validation
