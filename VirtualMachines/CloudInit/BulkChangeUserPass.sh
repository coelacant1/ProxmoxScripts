#!/bin/bash
#
# BulkChangeUserPass.sh
#
# Updates Cloud-Init username and password for a range of virtual machines (VMs) within a Proxmox VE environment.
# Sets a new username (optional) and password (required) for each VM, then regenerates Cloud-Init image.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkChangeUserPass.sh <start_vm_id> <end_vm_id> <password> [username]
#
# Arguments:
#   start_vm_id - The ID of the first VM to update.
#   end_vm_id   - The ID of the last VM to update.
#   password    - Password to set for the VMs.
#   username    - Optional. Username to set (preserves existing if not provided).
#
# Examples:
#   ./BulkChangeUserPass.sh 400 430 myNewPassword newuser
#   ./BulkChangeUserPass.sh 400 430 myNewPassword
#
# Function Index:
#   - usage
#   - parse_args
#   - change_user_pass
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
Usage: ${0##*/} <start_vm_id> <end_vm_id> <password> [username] [node]

Updates Cloud-Init username and password for a range of VMs.

Arguments:
  start_vm_id - The ID of the first VM to update
  end_vm_id   - The ID of the last VM to update
  password    - Password to set
  username    - Optional username to set
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

    START_VMID="$1"
    END_VMID="$2"
    PASSWORD="$3"
    USERNAME="${4:-}"
    # If 4th arg looks like a node, treat it as such
    if [[ -n "$USERNAME" ]] && [[ "$USERNAME" =~ ^(local|pve|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)  ]]; then
        TARGET_NODE="$USERNAME"
        USERNAME=""
    fi

    # Validate VM IDs are numeric
    if ! [[ "$START_VMID" =~ ^[0-9]+$ ]] || ! [[ "$END_VMID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    # Validate range
    if (( START_VMID > END_VMID )); then
        __err__ "Start VM ID must be less than or equal to end VM ID"
        exit 64
    fi
}

# --- change_user_pass --------------------------------------------------------
# @function change_user_pass
# @description Updates Cloud-Init username and password for a VM.
# @param 1 VM ID
# @param 2 Target node name
change_user_pass() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping on ${node}"
        return 0
    fi
    
    __update__ "Updating Cloud-Init credentials for VM ${vmid}... on ${node}"
    
    local cmd="qm set \"$vmid\" --cipassword \"$PASSWORD\" --node \"$node\""
    [[ -n "$USERNAME" ]] && cmd="qm set \"$vmid\" --ciuser \"$USERNAME\" --cipassword \"$PASSWORD\" --node \"$node\""
    
    if eval "$cmd" 2>/dev/null; then
        qm cloudinit dump "$vmid" --node "$node" 2>/dev/null || true
        __ok__ "Credentials updated for VM ${vmid} on ${node}"
    else
        __err__ "Failed to update credentials for VM ${vmid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and updates credentials.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk change user/pass: VMs ${START_VMID} to ${END_VMID} (cluster-wide)"
    [[ -n "$USERNAME" ]] && __info__ "Username: ${USERNAME}"
        # Update credentials for VMs in the specified range
    local failed_count=0
    local processed_count=0
    for (( vmid=START_VMID; vmid<=END_VMID; vmid++ )); do

        if change_user_pass "$vmid"; then

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
        __ok__ "Credentials updated successfully for all VMs"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, converted to cluster-wide
