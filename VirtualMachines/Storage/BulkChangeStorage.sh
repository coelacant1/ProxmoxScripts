#!/bin/bash
#
# BulkChangeStorage.sh
#
# Updates the storage location in VM configuration files for a range of VMs on a Proxmox node.
# Useful for moving VMs to a different storage solution or reorganizing storage resources.
# Automatically detects which node each VM is on and executes the operation cluster-wide.
#
# Usage:
#   ./BulkChangeStorage.sh <start_id> <end_id> <current_storage> <new_storage>
#
# Arguments:
#   start_id         - The starting VM ID for the operation.
#   end_id           - The ending VM ID for the operation.
#   current_storage  - The current storage identifier to replace.
#   new_storage      - The new storage identifier.
#
# Examples:
#   ./BulkChangeStorage.sh 100 200 local-lvm local-zfs
#
# Function Index:
#   - usage
#   - parse_args
#   - change_storage
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
Usage: ${0##*/} <start_id> <end_id> <current_storage> <new_storage>

Changes storage location in VM configuration files.

Arguments:
  start_id         - Starting VM ID
  end_id           - Ending VM ID
  current_storage  - Current storage identifier
  new_storage      - New storage identifier
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
    CURRENT_STORAGE="$3"
    NEW_STORAGE="$4"
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

# --- change_storage ----------------------------------------------------------
# @function change_storage
# @description Changes storage identifier in VM configuration file.
# @param 1 VM ID
change_storage() {
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
    
    if grep -q "$CURRENT_STORAGE" "$config_file"; then
        __update__ "Updating storage for VM ${vmid} on node ${node}..."
        if sed -i "s/$CURRENT_STORAGE/$NEW_STORAGE/g" "$config_file" 2>/dev/null; then
            __ok__ "Storage changed from ${CURRENT_STORAGE} to ${NEW_STORAGE} for VM ${vmid} on ${node}"
        else
            __err__ "Failed to update storage for VM ${vmid}"
            return 1
        fi
    else
        __update__ "${CURRENT_STORAGE} not found in VM ${vmid} config, skipping"
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - iterates through VM range and changes storage.
main() {
    __check_root__
    __check_proxmox__
    
    __info__ "Bulk change storage: VMs ${START_ID} to ${END_ID} (cluster-wide)"
    __info__ "Changing ${CURRENT_STORAGE} to ${NEW_STORAGE}"
        # Change storage for VMs in the specified range
    local failed_count=0
    local processed_count=0
    for (( vmid=START_ID; vmid<=END_ID; vmid++ )); do

        if change_storage "$vmid"; then

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
        __ok__ "All storage updates completed successfully"
    fi
}

parse_args "$@"
main

# Testing status:
#   - 2025-10-14: Updated to follow contributing guidelines, converted to cluster-wide
