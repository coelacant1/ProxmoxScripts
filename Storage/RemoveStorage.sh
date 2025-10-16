#!/bin/bash
#
# RemoveStorage.sh
#
# Removes storage from a Proxmox VE cluster.
# This script safely removes NFS, SMB/CIFS, PBS, or other storage types from the datacenter configuration.
#
# Usage:
#   ./RemoveStorage.sh <storage_id> [--force]
#
# Arguments:
#   storage_id - The unique identifier/name of the storage to remove
#
# Optional Arguments:
#   --force    - Skip confirmation prompt and force removal
#
# Examples:
#   ./RemoveStorage.sh NFS-Storage
#   ./RemoveStorage.sh SMB-Backup --force
#   ./RemoveStorage.sh PBS-Backup
#
# Function Index:
#   - usage
#   - parse_args
#   - check_storage_usage
#   - remove_storage
#   - main
#

set -u

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Global variables
STORAGE_ID=""
FORCE=false

# --- usage -------------------------------------------------------------------
# @function usage
# @description Prints usage information and exits.
usage() {
    cat <<-USAGE
Usage: ${0##*/} <storage_id> [--force]

Removes storage from the Proxmox cluster.

Arguments:
  storage_id - Storage identifier to remove

Optional Arguments:
  --force    - Skip confirmation and force removal

Examples:
  ${0##*/} NFS-Storage
  ${0##*/} SMB-Backup --force
  ${0##*/} PBS-Backup

Note:
  - Storage must not be in use by any VMs or containers
  - All data on the storage will become inaccessible after removal
  - This does not delete data from the storage server itself
USAGE
}

# --- parse_args --------------------------------------------------------------
# @function parse_args
# @description Parses and validates command-line arguments.
# @param @ All command-line arguments
parse_args() {
    if [[ $# -lt 1 ]]; then
        __err__ "Missing required argument: storage_id"
        usage
        exit 64
    fi

    STORAGE_ID="$1"
    shift

    # Parse optional arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                FORCE=true
                shift
                ;;
            *)
                __err__ "Unknown option: $1"
                usage
                exit 64
                ;;
        esac
    done

    # Validate storage exists
    if ! pvesm status --storage "$STORAGE_ID" &>/dev/null; then
        __err__ "Storage '${STORAGE_ID}' not found"
        __info__ "Available storage:"
        pvesm status 2>/dev/null | tail -n +2 | awk '{print "  - " $1}'
        exit 1
    fi
}

# --- check_storage_usage -----------------------------------------------------
# @function check_storage_usage
# @description Checks if storage is currently in use by VMs or containers.
# @return 0 if not in use, 1 if in use
check_storage_usage() {
    __info__ "Checking if storage is in use..."
    
    local in_use=false
    local usage_details=""

    # Check VMs
    for vmid in $(qm list 2>/dev/null | tail -n +2 | awk '{print $1}'); do
        if qm config "$vmid" 2>/dev/null | grep -q ":${STORAGE_ID}:"; then
            in_use=true
            usage_details+="  VM ${vmid}\n"
        fi
    done

    # Check LXC containers
    for ctid in $(pct list 2>/dev/null | tail -n +2 | awk '{print $1}'); do
        if pct config "$ctid" 2>/dev/null | grep -q ":${STORAGE_ID}:"; then
            in_use=true
            usage_details+="  CT ${ctid}\n"
        fi
    done

    if $in_use; then
        __warn__ "Storage '${STORAGE_ID}' is currently in use by:"
        echo -e "$usage_details"
        return 1
    else
        __ok__ "Storage is not in use"
        return 0
    fi
}

# --- remove_storage ----------------------------------------------------------
# @function remove_storage
# @description Removes the storage from cluster configuration.
remove_storage() {
    __info__ "Removing storage: ${STORAGE_ID}"

    if pvesm remove "$STORAGE_ID" 2>&1; then
        __ok__ "Storage '${STORAGE_ID}' removed successfully"
        return 0
    else
        __err__ "Failed to remove storage '${STORAGE_ID}'"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic - validates and removes storage.
main() {
    __check_root__
    __check_proxmox__

    # Get storage information
    __info__ "Storage information:"
    pvesm status --storage "$STORAGE_ID" 2>/dev/null || true
    echo

    # Check if storage is in use
    if ! check_storage_usage; then
        __warn__ "Storage is currently in use"
        if ! $FORCE; then
            __err__ "Cannot remove storage while in use"
            __info__ "Move or delete VMs/containers using this storage first"
            __info__ "Or use --force to override (not recommended)"
            exit 1
        else
            __warn__ "Proceeding with forced removal (--force specified)"
        fi
    fi

    # Confirm action with user
    if ! $FORCE; then
        echo
        __warn__ "This will remove storage '${STORAGE_ID}' from the cluster"
        __warn__ "Data on the storage server will remain but become inaccessible"
        
        if ! __prompt_user_yn__ "Are you sure you want to remove this storage?"; then
            __info__ "Operation cancelled by user"
            exit 0
        fi
    fi

    # Remove storage
    echo
    if remove_storage; then
        echo
        __ok__ "Storage removal complete"
        __info__ "Storage '${STORAGE_ID}' has been removed from the cluster"
    else
        exit 1
    fi
}

###############################################################################
# Script Entry Point
###############################################################################
parse_args "$@"
main
