#!/bin/bash
#
# BulkToggleStartAtBoot.sh
#
# Toggles the start at boot option for a range of virtual machines (VMs) within a Proxmox VE environment.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkToggleStartAtBoot.sh <start_vm_id> <end_vm_id> <enable|disable>
#
# Arguments:
#   start_vm_id     - The ID of the first VM to update.
#   end_vm_id       - The ID of the last VM to update.
#   enable|disable  - Set to 'enable' to enable start at boot, or 'disable' to disable it.
#
# Examples:
#   ./BulkToggleStartAtBoot.sh 400 430 enable
#   ./BulkToggleStartAtBoot.sh 400 430 disable
#
# Function Index:
#   - usage
#   - parse_args
#   - toggle_onboot
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- usage -------------------------------------------------------------------
# @function usage
# @description Prints usage information and exits.
usage() {
    cat <<-USAGE
Usage: ${0##*/} <start_vm_id> <end_vm_id> <enable|disable>

Toggles start at boot option for a range of VMs.

Arguments:
  start_vm_id     - The ID of the first VM to update
  end_vm_id       - The ID of the last VM to update
  enable|disable  - Action to perform
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
    ACTION="$3"
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
    
    # Determine onboot setting
    if [[ "$ACTION" == "enable" ]]; then
        ONBOOT_SETTING="1"
    elif [[ "$ACTION" == "disable" ]]; then
        ONBOOT_SETTING="0"
    else
        __err__ "Invalid action: ${ACTION}. Use 'enable' or 'disable'"
        exit 64
    fi
}

# --- toggle_onboot -----------------------------------------------------------
# @function toggle_onboot
# @description Toggles start at boot for a VM.
# @param 1 VM ID
# @param 2 Target node name
toggle_onboot() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping on ${node}"
        return 0
    fi
    
    __update__ "Setting start at boot to '${ACTION}' for VM ${vmid}... on ${node}"
    if qm set "$vmid" --onboot "$ONBOOT_SETTING" --node "$node" 2>/dev/null; then
        __ok__ "Start at boot ${ACTION}d for VM ${vmid} on ${node}"
    else
        __err__ "Failed to set start at boot for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and toggles start at boot.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk toggle start at boot (${ACTION}): VMs ${START_VM_ID} to ${END_VM_ID} (cluster-wide)"
        # Toggle start at boot for VMs in the specified range
    local failed_count=0
    local processed_count=0
    for (( vmid=START_VM_ID; vmid<=END_VM_ID; vmid++ )); do

        if toggle_onboot "$vmid"; then

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