#!/bin/bash
#
# BulkChangeNetwork.sh
#
# Automates changing network bridge configuration for a range of virtual machines (VMs) on a Proxmox VE cluster.
# Iterates through a specified range of VM IDs, modifying their configuration files to replace an old network bridge.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkChangeNetwork.sh <start_id> <end_id> <current_network> <new_network>
#
# Arguments:
#   start_id        - The starting VM ID in the range to be processed.
#   end_id          - The ending VM ID in the range to be processed.
#   current_network - The current network bridge (e.g., vmbr0) to be replaced.
#   new_network     - The new network bridge (e.g., vmbr1) to use.
#
# Examples:
#   ./BulkChangeNetwork.sh 100 200 vmbr0 vmbr1
#
# Function Index:
#   - usage
#   - parse_args
#   - change_network
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
Usage: ${0##*/} <start_id> <end_id> <current_network> <new_network>

Changes network bridge configuration in VM configuration files.

Arguments:
  start_id        - Starting VM ID
  end_id          - Ending VM ID
  current_network - Current network bridge (e.g., vmbr0)
  new_network     - New network bridge (e.g., vmbr1)
Examples:
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 4 ]]; then
        __err__ "Missing required arguments"
        usage
        exit 64
    fi

    START_ID="$1"
    END_ID="$2"
    CURRENT_NETWORK="$3"
    NEW_NETWORK="$4"
    # Validate IDs are numeric
    if ! [[ "$START_ID" =~ ^[0-9]+$ ]] || ! [[ "$END_ID" =~ ^[0-9]+$ ]]; then
        __err__ "VM IDs must be numeric"
        exit 64
    fi

    # Validate range
    if (( START_ID > END_ID )); then
        __err__ "Start ID must be less than or equal to end ID"
        exit 64
    fi
}

# --- change_network ----------------------------------------------------------
# @function change_network
# @description Changes network bridge in VM configuration file.
# @param 1 VM ID
change_network() {
    local vmid="$1"
    local node
    
    node=$(__get_vm_node__ "$vmid")
    
    if [[ -z "$node" ]]; then
        __update__ "VM ${vmid} not found in cluster, skipping"
        return 0
    fi
    
    local config_file="/etc/pve/nodes/${node}/qemu-server/${vmid}.conf"
    
    if [[ ! -f "$config_file" ]]; then
        __update__ "VM ${vmid} config does not exist, skipping"
        return 0
    fi
    
    if grep -q "$CURRENT_NETWORK" "$config_file"; then
        __update__ "Updating network bridge for VM ${vmid} on node ${node}..."
        if sed -i "s/$CURRENT_NETWORK/$NEW_NETWORK/g" "$config_file" 2>/dev/null; then
            __ok__ "Network changed from ${CURRENT_NETWORK} to ${NEW_NETWORK} for VM ${vmid} on ${node}"
        else
            __err__ "Failed to update network for VM ${vmid}"
            return 1
        fi
    else
        __update__ "${CURRENT_NETWORK} not found in VM ${vmid} config, skipping"
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and changes network.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk change network: VMs ${START_ID} to ${END_ID} (cluster-wide)"
    __info__ "Changing ${CURRENT_NETWORK} to ${NEW_NETWORK}"
        # Change network for VMs in the specified range
    local failed_count=0
    local processed_count=0
    for (( vmid=START_ID; vmid<=END_ID; vmid++ )); do

        if change_network "$vmid"; then

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
        __ok__ "All network changes completed successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, converted to cluster-wide
