#!/bin/bash
#
# RemoveStorage.sh
#
# Removes storage from a Proxmox VE cluster.
# This script safely removes NFS, SMB/CIFS, PBS, or other storage types from the datacenter configuration.
#
# Usage:
#   RemoveStorage.sh NFS-Storage
#   RemoveStorage.sh SMB-Backup --force
#   RemoveStorage.sh PBS-Backup
#
# Arguments:
#   storage_id - The unique identifier/name of the storage to remove
#   --force    - Skip confirmation prompt and force removal
#
# Notes:
#   - Storage must not be in use by any VMs or containers
#   - All data on the storage will become inaccessible after removal
#   - This does not delete data from the storage server itself
#
# Function Index:
#   - validate_custom_options
#   - check_storage_usage
#   - remove_storage
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- validate_custom_options -------------------------------------------------
# @function validate_custom_options
# @description Validates that storage exists.
validate_custom_options() {
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
main() {
    __check_root__
    __check_proxmox__

    # Parse arguments using ArgumentParser
    __parse_args__ "storage_id:string --force:flag" "$@"

    # Additional custom validation
    validate_custom_options

    # Display storage information
    __info__ "Storage to remove: ${STORAGE_ID}"
    __info__ "Storage details:"
    pvesm status --storage "$STORAGE_ID" 2>/dev/null || true

    # Check if storage is in use
    if ! check_storage_usage; then
        __err__ "Cannot remove storage that is currently in use"
        __err__ "Remove or migrate VMs/CTs using this storage first"
        exit 1
    fi

    # Confirm removal (unless --force)
    if [[ "$FORCE" != "true" ]]; then
        __warn__ "This will remove storage '${STORAGE_ID}' from cluster configuration"
        __warn__ "Data on the storage server will not be deleted"
        if ! __prompt_user_yn__ "Remove storage '${STORAGE_ID}'?"; then
            __info__ "Operation cancelled by user"
            exit 0
        fi
    fi

    # Remove storage
    remove_storage

    # Display remaining storage
    __info__ "Remaining storage in cluster:"
    pvesm status 2>/dev/null | tail -n +2 | awk '{print "  " $1 " (" $2 ")"}'
}

main "$@"

# Testing status:
#   - 2025-11-04: Refactored to use ArgumentParser.sh declarative parsing
#   - Removed manual usage() and parse_args() functions
#   - Now uses __parse_args__ with automatic validation
#   - Fixed __prompt_yes_no__ -> __prompt_user_yn__
