#!/bin/bash
#
# RestoreVM.sh
#
# Lists available backups for a VMID and restores to target storage.
# Supports both VM and container backups with appropriate options.
#
# Usage:
#   RestoreVM.sh <vmid> <source_storage> <target_storage>
#
# Arguments:
#   vmid           - VM or container ID to restore
#   source_storage - Storage containing backups
#   target_storage - Storage for restored VM/CT
#
# Examples:
#   RestoreVM.sh 101 IHKBackup local
#   RestoreVM.sh 113 PBS-Backup local-lvm
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse arguments
__parse_args__ "vmid:vmid source_storage:string target_storage:string" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __info__ "Searching for backups of VMID ${VMID} on storage ${SOURCE_STORAGE}"

    # List matching backups
    local -a backup_lines
    mapfile -t backup_lines < <(pvesm list "$SOURCE_STORAGE" --content backup 2>/dev/null | awk -v vmid="$VMID" '$NF == vmid')

    if [[ ${#backup_lines[@]} -eq 0 ]]; then
        __err__ "No backups found for VMID ${VMID} on storage ${SOURCE_STORAGE}"
        exit 1
    fi

    # Display backups
    echo
    echo "Available Backups:"
    echo "=================="
    local -a backups
    local idx=0
    for line in "${backup_lines[@]}"; do
        local backup_path
        backup_path=$(awk '{print $1}' <<< "$line")
        backups+=("$backup_path")
        echo "$idx) $backup_path"
        ((idx++))
    done
    echo

    # Select backup
    local sel_index
    while true; do
        read -rp "Select backup index to restore (0-$((${#backups[@]} - 1))): " sel_index
        if [[ "$sel_index" =~ ^[0-9]+$ ]] && [[ "$sel_index" -ge 0 ]] && [[ "$sel_index" -lt ${#backups[@]} ]]; then
            break
        fi
        echo "Invalid selection"
    done

    local selected_backup="${backups[$sel_index]}"
    local backup_type
    backup_type=$(awk '{print $2}' <<< "${backup_lines[$sel_index]}")

    __info__ "Selected: ${selected_backup}"

    # Restore based on type
    if [[ "$backup_type" == *"ct"* || "$selected_backup" == *"/ct/"* ]]; then
        __info__ "Detected container backup"

        local unprivileged=0
        if __prompt_yes_no__ "Restore as unprivileged container?"; then
            unprivileged=1
        fi

        local ignore_errors=""
        if __prompt_yes_no__ "Ignore unpack errors?"; then
            ignore_errors="--ignore-unpack-errors"
        fi

        __info__ "Restoring container ${VMID}"
        pct restore "$VMID" "$selected_backup" --storage "$TARGET_STORAGE" --unprivileged "$unprivileged" $ignore_errors
    else
        __info__ "Detected VM backup"
        __info__ "Restoring VM ${VMID}"
        qmrestore "$selected_backup" "$VMID" --storage "$TARGET_STORAGE"
    fi

    __ok__ "Restore completed successfully!"
}

main

# Testing status:
#   - Updated to use ArgumentParser and utility functions
#   - Pending validation
