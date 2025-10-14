#!/bin/bash
#
# BulkEnableGuestAgent.sh
#
# Enables the QEMU guest agent for a range of virtual machines (VMs) within a Proxmox VE environment.
# Optionally restarts VMs after enabling the guest agent to apply changes.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkEnableGuestAgent.sh <start_vm_id> <end_vm_id> [restart]
#
# Arguments:
#   start_vm_id - The ID of the first VM to update.
#   end_vm_id   - The ID of the last VM to update.
#   restart     - Optional. Set to 'restart' to restart VMs after enabling.
#
# Examples:
#   ./BulkEnableGuestAgent.sh 400 430
#   ./BulkEnableGuestAgent.sh 400 430 restart
#
# Function Index:
#   - usage
#   - parse_args
#   - enable_guest_agent
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
Usage: ${0##*/} <start_vm_id> <end_vm_id> [restart] [node]

Enables QEMU guest agent for a range of VMs.

Arguments:
  start_vm_id  - The ID of the first VM to update
  end_vm_id    - The ID of the last VM to update
  restart      - Optional. Set to 'restart' to restart VMs
Examples:
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    START_VM_ID="$1"
    END_VM_ID="$2"
    RESTART_OPTION="${3:-}"
    # If third argument is not "restart", it might be the node
    if [[ -n "$RESTART_OPTION" && "$RESTART_OPTION" != "restart" ]]; then
        TARGET_NODE="$RESTART_OPTION"
        RESTART_OPTION=""
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
}

# --- enable_guest_agent ------------------------------------------------------
# @function enable_guest_agent
# @description Enables guest agent for a VM and optionally restarts it.
# @param 1 VM ID
# @param 2 Target node name
enable_guest_agent() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping on ${node}"
        return 0
    fi
    
    __update__ "Enabling QEMU guest agent for VM ${vmid}... on ${node}"
    if qm set "$vmid" --agent 1 --node "$node" 2>/dev/null; then
        __ok__ "Guest agent enabled for VM ${vmid} on ${node}"
        
        if [[ "$RESTART_OPTION" == "restart" ]]; then
            __update__ "Restarting VM ${vmid}... on ${node}"
            if qm restart "$vmid" --node "$node" 2>/dev/null; then
                __ok__ "VM ${vmid} restarted on ${node}"
            else
                __err__ "Failed to restart VM ${vmid}"
                return 1
            fi
        fi
    else
        __err__ "Failed to enable guest agent for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and enables guest agent.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk enable guest agent: VMs ${START_VM_ID} to ${END_VM_ID} (cluster-wide)"
        # Enable guest agent for VMs in the specified range
    local failed_count=0
    local processed_count=0
    for (( vmid=START_VM_ID; vmid<=END_VM_ID; vmid++ )); do

        if enable_guest_agent "$vmid"; then

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
        __ok__ "All VMs updated successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, converted to cluster-wide