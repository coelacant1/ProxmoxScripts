#!/bin/bash
#
# BulkSetCPUTypeCoreCount.sh
#
# Sets the CPU type and number of cores for a range of virtual machines (VMs) within a Proxmox VE environment.
# By default, uses current CPU type unless specified.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkSetCPUTypeCoreCount.sh <start_vm_id> <end_vm_id> <num_cores> [cpu_type]
#
# Arguments:
#   start_vm_id - The ID of the first VM to update.
#   end_vm_id   - The ID of the last VM to update.
#   num_cores   - The number of CPU cores to assign to each VM.
#   cpu_type    - Optional. CPU type (e.g., 'host', 'kvm64'). Retains current if not provided.
#
# Examples:
#   ./BulkSetCPUTypeCoreCount.sh 400 430 4
#   ./BulkSetCPUTypeCoreCount.sh 400 430 4 host
#
# Function Index:
#   - usage
#   - parse_args
#   - set_cpu_config
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- usage -------------------------------------------------------------------
# @function usage
# @description Prints usage information and exits.
usage() {
    cat <<-USAGE
Usage: ${0##*/} <start_vm_id> <end_vm_id> <num_cores> [cpu_type] [node]

Sets CPU type and core count for a range of VMs.

Arguments:
  start_vm_id - The ID of the first VM to update
  end_vm_id   - The ID of the last VM to update
  num_cores   - Number of CPU cores to assign
  cpu_type    - Optional CPU type (e.g., 'host', 'kvm64')
Examples:
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 3 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    START_VM_ID="$1"
    END_VM_ID="$2"
    NUM_CORES="$3"
    CPU_TYPE="${4:-}"
    # If 4th arg looks like a node, adjust
    if [[ -n "$CPU_TYPE" ]] && [[ "$CPU_TYPE" =~ ^(local|pve|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
        TARGET_NODE="$CPU_TYPE"
        CPU_TYPE=""
    fi

    # Validate VM IDs are numeric
    if ! [[ "$START_VM_ID" =~ ^[0-9]+$ ]] || ! [[ "$END_VM_ID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    # Validate range
    if (( START_VM_ID > END_VM_ID )); then
        __err__ "Start VM ID must be less than or equal to end VM ID"
        exit 64
    fi
    
    # Validate num_cores is numeric
    if ! [[ "$NUM_CORES" =~ ^[0-9]+$ ]]; then
        __err__ "Number of cores must be numeric"
        exit 64
    fi
}

# --- set_cpu_config ----------------------------------------------------------
# @function set_cpu_config
# @description Sets CPU configuration for a VM.
# @param 1 VM ID
# @param 2 Target node name
set_cpu_config() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping on ${node}"
        return 0
    fi
    
    __update__ "Updating CPU configuration for VM ${vmid}... on ${node}"
    
    if qm set "$vmid" --cores "$NUM_CORES" --node "$node" 2>/dev/null; then
        if [[ -n "$CPU_TYPE" ]]; then
            if qm set "$vmid" --cpu "$CPU_TYPE" --node "$node" 2>/dev/null; then
                __ok__ "CPU set to ${NUM_CORES} cores, type: ${CPU_TYPE} for VM ${vmid} on ${node}"
            else
                __err__ "Failed to set CPU type for VM ${vmid}"
                return 1
            fi
        else
            __ok__ "CPU set to ${NUM_CORES} cores for VM ${vmid} on ${node}"
        fi
    else
        __err__ "Failed to set CPU cores for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and sets CPU config.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk set CPU config: VMs ${START_VM_ID} to ${END_VM_ID} (cluster-wide)"
    __info__ "Cores: ${NUM_CORES}"
    [[ -n "$CPU_TYPE" ]] && __info__ "CPU Type: ${CPU_TYPE}"
        # Set CPU config for VMs in the specified range
    local failed_count=0
    local processed_count=0
    for (( vmid=START_VM_ID; vmid<=END_VM_ID; vmid++ )); do

        if set_cpu_config "$vmid"; then

            ((processed_count++))

        else

            ((failed_count++))

        fi

    done
    
    __info__ "Processed ${processed_count} VM(s)"
    
    
    
    if (( failed_count > 0 )); then
        __err__ "Operation completed with ${failed_count} failure(s)"
        exit 1
    else
        __ok__ "CPU configuration updated successfully for all VMs"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, converted to cluster-wide