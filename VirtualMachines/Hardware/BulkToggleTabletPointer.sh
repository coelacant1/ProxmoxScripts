#!/bin/bash
#
# BulkToggleTabletPointer.sh
#
# Enables or disables the tablet/pointer device for a range of virtual machines (VMs) within a Proxmox VE environment.
# The tablet device is used for absolute mouse positioning in VMs. This script allows toggling the setting on or off.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkToggleTabletPointer.sh <start_vm_id> <end_vm_id> <enable|disable>
#
# Arguments:
#   start_vm_id - The ID of the first VM to update.
#   end_vm_id   - The ID of the last VM to update.
#   action      - Either 'enable' or 'disable' (or '1' or '0')
#
# Examples:
#   ./BulkToggleTabletPointer.sh 400 430 disable
#   ./BulkToggleTabletPointer.sh 100 105 enable
#   ./BulkToggleTabletPointer.sh 200 210 0
#
# Function Index:
#   - usage
#   - parse_args
#   - toggle_tablet_pointer
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

Enables or disables the tablet/pointer device for a range of VMs cluster-wide.

Arguments:
  start_vm_id - The ID of the first VM to update
  end_vm_id   - The ID of the last VM to update
  action      - 'enable', 'disable', '1', or '0'

Examples:
  ${0##*/} 400 430 disable
  ${0##*/} 100 105 enable
  ${0##*/} 200 210 0

Note:
  - VMs must be restarted for changes to take effect
  - Disabling can improve performance or compatibility
  - Enabling provides better mouse integration
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
    local action_input="$3"

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

    # Parse action
    case "${action_input,,}" in
        enable|1|on|true)
            TABLET_VALUE=1
            ACTION_NAME="enable"
            ;;
        disable|0|off|false)
            TABLET_VALUE=0
            ACTION_NAME="disable"
            ;;
        *)
            __err__ "Invalid action: ${action_input}. Use 'enable' or 'disable'"
            exit 64
            ;;
    esac
}

# --- toggle_tablet_pointer ---------------------------------------------------
# @function toggle_tablet_pointer
# @description Enables or disables the tablet pointer device for a VM.
# @param 1 VM ID
toggle_tablet_pointer() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    __update__ "${ACTION_NAME^}ing tablet pointer for VM ${vmid} on ${node}..."
    
    # Check current tablet setting
    local current_tablet
    current_tablet=$(qm config "$vmid" --node "$node" 2>/dev/null | grep -E "^tablet:" | awk '{print $2}')
    
    # If already at desired state, skip
    if [[ "$current_tablet" == "$TABLET_VALUE" ]]; then
        __ok__ "Tablet pointer already ${ACTION_NAME}d for VM ${vmid} on ${node}"
        return 0
    fi
    
    # Toggle tablet pointer
    if qm set "$vmid" --tablet "$TABLET_VALUE" --node "$node" 2>/dev/null; then
        __ok__ "Tablet pointer ${ACTION_NAME}d for VM ${vmid} on ${node}"
        
        # Check if VM is running and warn
        local vm_status
        vm_status=$(qm status "$vmid" --node "$node" 2>/dev/null | awk '{print $2}')
        if [[ "$vm_status" == "running" ]]; then
            __warn__ "VM ${vmid} is running - restart required for changes to take effect"
        fi
        return 0
    else
        __err__ "Failed to ${ACTION_NAME} tablet pointer for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and toggles tablet pointer.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk ${ACTION_NAME} tablet pointer: VMs ${START_VM_ID} to ${END_VM_ID} (cluster-wide)"
    
    # Confirm action
    if ! __prompt_user_yn__ "${ACTION_NAME^} tablet pointer for VMs ${START_VM_ID}-${END_VM_ID}?"; then
        __info__ "Operation cancelled by user"
        exit 0
    fi
    
    # Toggle tablet pointer for VMs in the specified range
    local failed_count=0
    local processed_count=0
    local skipped_count=0
    
    for (( vmid=START_VM_ID; vmid<=END_VM_ID; vmid++ )); do
        if toggle_tablet_pointer "$vmid"; then
            ((processed_count++))
        else
            ((failed_count++))
        fi
    done
    
    # Summary
    echo
    __info__ "Operation complete:"
    __info__ "  Processed: ${processed_count}"
    if (( failed_count > 0 )); then
        __warn__ "  Failed: ${failed_count}"
    fi
    
    if (( failed_count > 0 )); then
        exit 1
    fi
}

###############################################################################
# Script Entry Point
###############################################################################
parse_args "$@"
main
