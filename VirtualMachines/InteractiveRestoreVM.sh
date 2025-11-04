#!/bin/bash
#
# InteractiveRestoreVM.sh
#
# Interactively lists all available VM (qemu) backups from a storage, allowing the user
# to select which backup to restore. The script automatically detects the VMID from
# the backup and handles only VM backups.
#
# Usage:
#   InteractiveRestoreVM.sh <source-storage> <target-storage> [new-vmid]
#
# Arguments:
#   source-storage - Storage containing the backups (e.g., 'PBS-Backup', 'local')
#   target-storage - Storage where VM will be restored (e.g., 'local-lvm', 'local')
#   new-vmid       - Optional: New VMID to use (defaults to original VMID from backup)
#
# Examples:
#   # List VM backups from PBS-Backup and restore to local-lvm
#   InteractiveRestoreVM.sh PBS-Backup local-lvm
#
#   # Restore with a new VMID
#   InteractiveRestoreVM.sh PBS-Backup local-lvm 999
#
#   # Restore from local storage
#   InteractiveRestoreVM.sh local local
#
# Notes:
#   - Only handles VM (qemu) backups
#   - For container (LXC) backups, use LXC/InteractiveRestoreCT.sh
#
# Function Index:
#   - parse_backup_info
#   - list_backups
#   - select_backup
#   - restore_vm
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
NEW_VMID=""
declare -a BACKUP_PATHS
declare -a BACKUP_VMIDS
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
    local backup_vmid

    # Parse fields: STORAGE:backup/path TYPE content SIZE VMID
    backup_path=$(echo "$line" | awk '{print $1}')
    backup_type=$(echo "$line" | awk '{print $2}')
    backup_size=$(echo "$line" | awk '{print $4}')
    backup_vmid=$(echo "$line" | awk '{print $NF}')

    # Extract date from backup path if available
    local backup_date="Unknown"
    if [[ "$backup_path" =~ ([0-9]{4}[-_][0-9]{2}[-_][0-9]{2}[-_][0-9]{2}[-_:][0-9]{2}[-_:][0-9]{2}) ]]; then
        backup_date="${BASH_REMATCH[1]}"
        backup_date="${backup_date//_/ }"  # Replace underscores with spaces
        backup_date="${backup_date//-/:}"  # Fix time separators
    fi

    BACKUP_PATHS+=("$backup_path")
    BACKUP_VMIDS+=("$backup_vmid")
    BACKUP_TYPES+=("$backup_type")
    BACKUP_SIZES+=("$backup_size")
    BACKUP_DATES+=("$backup_date")
}

# --- list_backups ------------------------------------------------------------
# @function list_backups
# @description Lists all available VM backups from the source storage
list_backups() {
    __info__ "Scanning for VM backups on storage: ${SOURCE_STORAGE}"

    local backup_output
    if ! backup_output=$(pvesm list "$SOURCE_STORAGE" --content backup 2>&1); then
        __err__ "Failed to list backups from storage '${SOURCE_STORAGE}'"
        __info__ "Make sure the storage exists and is accessible"
        exit 1
    fi

    # Parse each backup line, filtering for VM backups only
    while IFS= read -r line; do
        # Skip header line
        [[ "$line" =~ ^Volid ]] && continue
        [[ -z "$line" ]] && continue

        # Get backup type
        local backup_type=$(echo "$line" | awk '{print $2}')

        # Only process VM backups (skip container backups)
        case "$backup_type" in
            pbs-vm|vma|qemu)
                parse_backup_info "$line"
                ;;
            pbs-ct|vzdump|lxc)
                # Skip container backups
                continue
                ;;
        esac
    done <<< "$backup_output"

    if [[ ${#BACKUP_PATHS[@]} -eq 0 ]]; then
        __err__ "No VM backups found on storage '${SOURCE_STORAGE}'"
        __info__ "For container backups, use LXC/InteractiveRestoreCT.sh"
        exit 1
    fi

    __ok__ "Found ${#BACKUP_PATHS[@]} VM backup(s)"
}

# --- select_backup -----------------------------------------------------------
# @function select_backup
# @description Displays backups and prompts user to select one
# @return Selected backup index
select_backup() {
    echo
    echo "Available Backups:"
    echo "==================="

    for i in "${!BACKUP_PATHS[@]}"; do
        local size_mb=$((BACKUP_SIZES[i] / 1024 / 1024))
        local type_display="${BACKUP_TYPES[i]}"

        # Friendly type names
        case "${BACKUP_TYPES[i]}" in
            pbs-vm|vma|qemu) type_display="VM" ;;
            pbs-ct|vzdump|lxc) type_display="CT" ;;
        esac

        printf "%3d) VMID: %-5s Type: %-4s Size: %6d MB  Date: %s\n" \
            $((i+1)) \
            "${BACKUP_VMIDS[i]}" \
            "$type_display" \
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

# --- restore_vm --------------------------------------------------------------
# @function restore_vm
# @description Restores a VM (qemu) backup
restore_vm() {
    local backup_path="$1"
    local vmid="$2"

    __info__ "Restoring VM backup to VMID ${vmid}"

    # Build restore command
    local cmd="qmrestore \"${backup_path}\" ${vmid} --storage \"${TARGET_STORAGE}\""

    __info__ "Executing: ${cmd}"

    if eval "$cmd" 2>&1; then
        __ok__ "VM ${vmid} restored successfully"
        return 0
    else
        __err__ "Failed to restore VM ${vmid}"
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
        echo "Usage: $0 <source-storage> <target-storage> [new-vmid]"
        echo
        echo "Examples:"
        echo "  $0 PBS-Backup local-lvm"
        echo "  $0 PBS-Backup local-lvm 999"
        exit 64
    fi

    SOURCE_STORAGE="$1"
    TARGET_STORAGE="$2"
    NEW_VMID="${3:-}"

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
    local original_vmid="${BACKUP_VMIDS[$selected_idx]}"
    local backup_type="${BACKUP_TYPES[$selected_idx]}"

    # Determine target VMID
    local target_vmid="${NEW_VMID:-$original_vmid}"

    # Check if VMID already exists
    if qm status "$target_vmid" &>/dev/null || pct status "$target_vmid" &>/dev/null; then
        __err__ "VMID ${target_vmid} already exists"
        __info__ "Use a different VMID or remove the existing VM/CT first"
        exit 1
    fi

    # Display restore summary
    echo
    echo "Restore Summary:"
    echo "================"
    echo "  Backup:        ${backup_path}"
    echo "  Original VMID: ${original_vmid}"
    echo "  Target VMID:   ${target_vmid}"
    echo "  Type:          VM (qemu)"
    echo "  From:          ${SOURCE_STORAGE}"
    echo "  To:            ${TARGET_STORAGE}"
    echo

    if ! __prompt_user_yn__ "Proceed with restore?"; then
        echo "Restore cancelled"
        exit 0
    fi

    # Restore the VM
    restore_vm "$backup_path" "$target_vmid"

    # Show final status
    echo
    __info__ "Checking restored VM status"
    qm config "$target_vmid" | head -10

    echo
    __ok__ "Restore operation completed successfully!"
    __info__ "VMID ${target_vmid} is ready to use"
}

###############################################################################
# Script Entry Point
###############################################################################
main "$@"
