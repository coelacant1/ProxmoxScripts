#!/bin/bash
#
# BulkSetCPUTypeCoreCount.sh
#
# Sets the CPU type and number of cores for a range of virtual machines (VMs) within a Proxmox VE environment.
# By default, uses current CPU type unless specified.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   BulkSetCPUTypeCoreCount.sh <start_vm_id> <end_vm_id> <num_cores> [cpu_type]
#
# Arguments:
#   start_vm_id - The ID of the first VM to update.
#   end_vm_id   - The ID of the last VM to update.
#   num_cores   - The number of CPU cores to assign to each VM.
#   cpu_type    - Optional. CPU type (e.g., 'host', 'kvm64'). Retains current if not provided.
#
# Examples:
#   BulkSetCPUTypeCoreCount.sh 400 430 4
#   BulkSetCPUTypeCoreCount.sh 400 430 4 host
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
__parse_args__ "start_vmid:vmid end_vmid:vmid num_cores:cpu cpu_type:string:?" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Bulk set CPU config: VMs ${START_VMID} to ${END_VMID} (cluster-wide)"
    __info__ "Cores: ${NUM_CORES}"
    [[ -n "${CPU_TYPE:-}" ]] && __info__ "CPU Type: ${CPU_TYPE}"

    # Local callback for bulk operation
    set_cpu_config_callback() {
        local vmid="$1"
        local node

        node=$(__get_vm_node__ "$vmid")

        if [[ -z "$node" ]]; then
            __update__ "VM ${vmid} not found in cluster"
            return 1
        fi

        __update__ "Updating CPU configuration for VM ${vmid}..."

        if __node_exec__ "$node" "qm set ${vmid} --cores ${NUM_CORES}" 2>/dev/null; then
            if [[ -n "${CPU_TYPE:-}" ]]; then
                if __node_exec__ "$node" "qm set ${vmid} --cpu ${CPU_TYPE}" 2>/dev/null; then
                    return 0
                else
                    return 1
                fi
            else
                return 0
            fi
        else
            return 1
        fi
    }

    # Use BulkOperations framework
    __bulk_vm_operation__ --name "CPU Configuration" --report "$START_VMID" "$END_VMID" set_cpu_config_callback

    # Display summary
    __bulk_summary__

    [[ $BULK_FAILED -gt 0 ]] && exit 1
    __ok__ "CPU configuration updated successfully!"
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
# - 2025-11-24: Fixed argument type from 'int' to 'cpu' for num_cores validation
# - 2025-11-20: Updated to use ArgumentParser and BulkOperations framework
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# - 2025-11-24: FIXED CRITICAL BUG: qm commands were using --node flag which doesn't
#   exist. Changed to use __node_exec__ to execute commands on correct node via ssh
# - 2025-11-24: Fixed num_cores using incorrect 'int' type instead of 'cpu'
#
# Known issues:
# -
#

