#!/bin/bash
#
# BulkSetMemoryConfig.sh
#
# Sets the amount of memory allocated to a range of virtual machines (VMs) within a Proxmox VE environment.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   BulkSetMemoryConfig.sh <start_vm_id> <end_vm_id> <memory_size>
#
# Arguments:
#   start_vm_id - The ID of the first VM to update.
#   end_vm_id   - The ID of the last VM to update.
#   memory_size - The amount of memory (in MB) to allocate to each VM.
#
# Examples:
#   BulkSetMemoryConfig.sh 400 430 8192
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
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"
# shellcheck source=Utilities/Operations.sh
source "${UTILITYPATH}/Operations.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "start_vmid:vmid end_vmid:vmid memory_size:memory" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk set memory: VMs ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "Memory: ${MEMORY_SIZE}MB"

    # Local callback for bulk operation
    set_memory_callback() {
        local vmid="$1"
        local node

        node=$(__get_vm_node__ "$vmid")

        if [[ -z "$node" ]]; then
            __update__ "VM ${vmid} not found in cluster"
            return 1
        fi

        __update__ "Setting memory to ${MEMORY_SIZE}MB for VM ${vmid}..."
        if __node_exec__ "$node" "qm set ${vmid} --memory ${MEMORY_SIZE}" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    }

    # Use BulkOperations framework
    __bulk_vm_operation__ --name "Memory Configuration" --report "$START_VMID" "$END_VMID" set_memory_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "Memory configuration updated successfully!"
}

main

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-24
#
# Changes:
# - 2025-11-24: Fixed qm command execution to use __node_exec__ for cluster-aware operations
# - 2025-11-24: Added Operations.sh source for __node_exec__ function
# - 2025-11-24: Fixed argument type from 'int' to 'memory' for proper validation
# - 2025-11-20: Updated to use ArgumentParser and BulkOperations framework
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-24: FIXED CRITICAL BUG: qm commands were using --node flag which doesn't
#   exist. Changed to use __node_exec__ to execute commands on correct node via ssh
# - 2025-11-24: Fixed memory_size using incorrect 'int' type instead of 'memory'
#
# Known issues:
# -
#

