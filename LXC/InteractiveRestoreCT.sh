#!/bin/bash
#
# InteractiveRestoreCT.sh
#
# Interactively lists all available container (LXC) backups from a storage, allowing
# the user to select which backup to restore. The script automatically detects the CTID
# from the backup and handles only container backups.
#
# Usage:
#   InteractiveRestoreCT.sh <source-storage> <target-storage> [new-ctid]
#
# Arguments:
#   source-storage - Storage containing the backups (e.g., 'PBS-Backup', 'local')
#   target-storage - Storage where container will be restored (e.g., 'local', 'local-lvm')
#   new-ctid       - Optional: New CTID to use (defaults to original CTID from backup)
#
# Examples:
#   # List container backups from PBS-Backup and restore to local
#   InteractiveRestoreCT.sh PBS-Backup local
#
#   # Restore with a new CTID
#   InteractiveRestoreCT.sh PBS-Backup local 999
#
#   # Restore from local storage
#   InteractiveRestoreCT.sh local local
#
# Notes:
#   - Only handles container (LXC) backups
#   - For VM (qemu) backups, use VirtualMachines/InteractiveRestoreVM.sh
#   - Prompts for unprivileged and unpack-error options during restore
#
# Function Index:
#   - parse_backup_info
#   - list_backups
#   - select_backup
#   - restore_container
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Global variables
SOURCE_STORAGE=""
TARGET_STORAGE=""
NEW_CTID=""
declare -a BACKUP_PATHS
declare -a BACKUP_CTIDS
declare -a BACKUP_TYPES
declare -a BACKUP_SIZES
declare -a BACKUP_DATES

# --- parse_backup_info -------------------------------------------------------
# @function parse_backup_info
# @description Parses backup information from pvesm list output
parse_backup_info() {
    local line="$1"
    local backup_path
    local backup_type
    local backup_size
    local backup_ctid

    # Parse fields: STORAGE:backup/path TYPE content SIZE CTID
    backup_path=$(echo "$line" | awk '{print $1}')
    backup_type=$(echo "$line" | awk '{print $2}')
    backup_size=$(echo "$line" | awk '{print $4}')
    backup_ctid=$(echo "$line" | awk '{print $NF}')

    # Extract date from backup path if available
    local backup_date="Unknown"
    if [[ "$backup_path" =~ ([0-9]{4}[-_][0-9]{2}[-_][0-9]{2}[-_][0-9]{2}[-_:][0-9]{2}[-_:][0-9]{2}) ]]; then
        backup_date="${BASH_REMATCH[1]}"
        backup_date="${backup_date//_/ }"  # Replace underscores with spaces
        backup_date="${backup_date//-/:}"  # Fix time separators
    fi

    BACKUP_PATHS+=("$backup_path")
    BACKUP_CTIDS+=("$backup_ctid")
    BACKUP_TYPES+=("$backup_type")
    BACKUP_SIZES+=("$backup_size")
    BACKUP_DATES+=("$backup_date")
}

# --- list_backups ------------------------------------------------------------
# @function list_backups
# @description Lists all available container backups from the source storage
list_backups() {
    __info__ "Scanning for container backups on storage: ${SOURCE_STORAGE}"

    local backup_output
    if ! backup_output=$(pvesm list "$SOURCE_STORAGE" --content backup 2>&1); then
        __err__ "Failed to list backups from storage '${SOURCE_STORAGE}'"
        __info__ "Make sure the storage exists and is accessible"
        exit 1
    fi

    # Parse each backup line, filtering for container backups only
    while IFS= read -r line; do
        # Skip header line
        [[ "$line" =~ ^Volid ]] && continue
        [[ -z "$line" ]] && continue

        # Get backup type
        local backup_type=$(echo "$line" | awk '{print $2}')

        # Only process container backups (skip VM backups)
        case "$backup_type" in
            pbs-ct|vzdump|lxc)
                parse_backup_info "$line"
                ;;
            pbs-vm|vma|qemu)
                # Skip VM backups
                continue
                ;;
        esac
    done <<< "$backup_output"

    if [[ ${#BACKUP_PATHS[@]} -eq 0 ]]; then
        __err__ "No container backups found on storage '${SOURCE_STORAGE}'"
        __info__ "For VM backups, use VirtualMachines/InteractiveRestoreVM.sh"
        exit 1
    fi

    __ok__ "Found ${#BACKUP_PATHS[@]} container backup(s)"
}

# --- select_backup -----------------------------------------------------------
# @function select_backup
# @description Displays backups and prompts user to select one
# @return Selected backup index
select_backup() {
    echo
    echo "Available Container Backups:"
    echo "============================"

    for i in "${!BACKUP_PATHS[@]}"; do
        local size_mb=$((BACKUP_SIZES[i] / 1024 / 1024))

        printf "%3d) CTID: %-5s Size: %6d MB  Date: %s\n" \
            $((i+1)) \
            "${BACKUP_CTIDS[i]}" \
            "$size_mb" \
            "${BACKUP_DATES[i]}"
        echo "     ${BACKUP_PATHS[i]}"
    done

    echo
    local selection
    while true; do
        read -p "Select backup to restore (1-${#BACKUP_PATHS[@]}) or 'q' to quit: " selection

        if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
            echo "Operation cancelled"
            exit 0
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] && \
           [[ "$selection" -ge 1 ]] && \
           [[ "$selection" -le ${#BACKUP_PATHS[@]} ]]; then
            return $((selection - 1))
        fi

        echo "Invalid selection. Please enter a number between 1 and ${#BACKUP_PATHS[@]}"
    done
}

# --- restore_container -------------------------------------------------------
# @function restore_container
# @description Restores a container (lxc) backup
restore_container() {
    local backup_path="$1"
    local ctid="$2"

    echo
    __info__ "Container restore options"

    # Ask about unprivileged
    local unprivileged=""
    if __prompt_user_yn__ "Restore as unprivileged container?"; then
        unprivileged="--unprivileged 1"
    fi

    # Ask about ignore-unpack-errors
    local ignore_errors=""
    if __prompt_user_yn__ "Ignore unpack errors? (useful for some backups)"; then
        ignore_errors="--ignore-unpack-errors 1"
    fi

    __info__ "Restoring container backup to CTID ${ctid}"

    # Build restore command
    local cmd="pct restore ${ctid} \"${backup_path}\" --storage \"${TARGET_STORAGE}\" ${unprivileged} ${ignore_errors}"

    __info__ "Executing: ${cmd}"

    if eval "$cmd" 2>&1; then
        __ok__ "Container ${ctid} restored successfully"
        return 0
    else
        __err__ "Failed to restore container ${ctid}"
        return 1
    fi
}

# --- main --------------------------------------------------------------------
# @function main
# @description Main script logic
main() {
    __check_root__
    __check_proxmox__

    # Parse arguments
    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments"
        echo "Usage: $0 <source-storage> <target-storage> [new-ctid]"
        echo
        echo "Examples:"
        echo "  $0 PBS-Backup local"
        echo "  $0 PBS-Backup local 999"
        exit 64
    fi

    SOURCE_STORAGE="$1"
    TARGET_STORAGE="$2"
    NEW_CTID="${3:-}"

    # Validate storages exist
    if ! pvesm status --storage "$SOURCE_STORAGE" &>/dev/null; then
        __err__ "Source storage '${SOURCE_STORAGE}' not found"
        __info__ "Available storages:"
        pvesm status | tail -n +2 | awk '{print "  - " $1}'
        exit 1
    fi

    if ! pvesm status --storage "$TARGET_STORAGE" &>/dev/null; then
        __err__ "Target storage '${TARGET_STORAGE}' not found"
        __info__ "Available storages:"
        pvesm status | tail -n +2 | awk '{print "  - " $1}'
        exit 1
    fi

    # List and select backup
    list_backups
    select_backup
    local selected_idx=$?

    # Get selected backup details
    local backup_path="${BACKUP_PATHS[$selected_idx]}"
    local original_ctid="${BACKUP_CTIDS[$selected_idx]}"
    local backup_type="${BACKUP_TYPES[$selected_idx]}"

    # Determine target CTID
    local target_ctid="${NEW_CTID:-$original_ctid}"

    # Check if CTID already exists
    if qm status "$target_ctid" &>/dev/null || pct status "$target_ctid" &>/dev/null; then
        __err__ "CTID ${target_ctid} already exists"
        __info__ "Use a different CTID or remove the existing VM/CT first"
        exit 1
    fi

    # Display restore summary
    echo
    echo "Restore Summary:"
    echo "================"
    echo "  Backup:        ${backup_path}"
    echo "  Original CTID: ${original_ctid}"
    echo "  Target CTID:   ${target_ctid}"
    echo "  Type:          Container (LXC)"
    echo "  From:          ${SOURCE_STORAGE}"
    echo "  To:            ${TARGET_STORAGE}"
    echo

    if ! __prompt_user_yn__ "Proceed with restore?"; then
        echo "Restore cancelled"
        exit 0
    fi

    # Restore the container
    restore_container "$backup_path" "$target_ctid"

    # Show final status
    echo
    __info__ "Checking restored container status"
    pct config "$target_ctid" | head -10

    echo
    __ok__ "Restore operation completed successfully!"
    __info__ "CTID ${target_ctid} is ready to use"
}

###############################################################################
# Script Entry Point
###############################################################################
main "$@"

# Testing status:
#   - Updated with utility functions
#   - Pending validation
