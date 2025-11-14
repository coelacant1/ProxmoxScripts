#!/bin/bash
#
# RemoveLocalLVMAndExpand.sh
#
# Removes local-lvm volume (pve/data) and expands root volume to reclaim space.
# WARNING: This is DESTRUCTIVE. Backup all VMs/containers on local-lvm first.
#
# Usage:
#   RemoveLocalLVMAndExpand.sh [--force]
#
# Examples:
#   RemoveLocalLVMAndExpand.sh                    # Interactive mode with prompts
#   RemoveLocalLVMAndExpand.sh --force            # Skip confirmation prompt
#   
# Note:
#   - When running from GUI, NON_INTERACTIVE is automatically set
#   - Destructive operations require --force in non-interactive mode
#   - This prevents accidental data loss in automated contexts
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Parse flags
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=1
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: RemoveLocalLVMAndExpand.sh [--force]"
            echo ""
            echo "Note: Non-interactive mode is detected via NON_INTERACTIVE environment variable"
            echo "      (automatically set by GUI and remote execution frameworks)"
            exit 1
            ;;
    esac
done

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __install_or_prompt__ "lvm2"
    __install_or_prompt__ "e2fsprogs"
    __install_or_prompt__ "xfsprogs"

    __warn__ "DESTRUCTIVE: This will remove 'local-lvm' (pve/data) and ALL data on it"
    __warn__ "Ensure you have backups of all VMs/containers on local-lvm"

    # Safety check for non-interactive + destructive operation
    # Use NON_INTERACTIVE environment variable (set by GUI and remote execution frameworks)
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]] && [[ $FORCE -eq 0 ]]; then
        __err__ "Destructive operation requires --force flag in non-interactive mode"
        __err__ "Usage: RemoveLocalLVMAndExpand.sh --force"
        __err__ "Or add '--force' to parameters in GUI"
        exit 1
    fi

    # Prompt for confirmation (unless force is set)
    if [[ $FORCE -eq 1 ]]; then
        __info__ "Force mode enabled - proceeding without confirmation"
    elif ! __prompt_user_yn__ "Proceed with removing local-lvm?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    # Remove pve/data logical volume
    __info__ "Removing logical volume 'pve/data'"
    if lvdisplay /dev/pve/data &>/dev/null; then
        if lvremove -f /dev/pve/data 2>&1; then
            __ok__ "pve/data removed"
        else
            __err__ "Failed to remove pve/data"
            exit 1
        fi
    else
        __info__ "pve/data not found or already removed"
    fi

    # Check for pve/root
    if ! lvdisplay /dev/pve/root &>/dev/null; then
        __err__ "pve/root not found. System may not use expected LVM layout"
        exit 1
    fi

    # Expand pve/root
    __info__ "Expanding pve/root to use all free space"
    if lvextend -l +100%FREE /dev/pve/root 2>&1; then
        __ok__ "pve/root expanded"
    else
        __err__ "Failed to expand pve/root"
        exit 1
    fi

    # Resize filesystem
    __info__ "Resizing filesystem"
    if grep -qs "/dev/mapper/pve-root" /proc/mounts && blkid /dev/pve/root | grep -qi 'TYPE="ext4"'; then
        __info__ "Detected ext4 filesystem, using resize2fs"
        if resize2fs /dev/pve/root 2>&1; then
            __ok__ "Filesystem resized"
        else
            __err__ "Failed to resize filesystem"
            exit 1
        fi
    elif grep -qs "/dev/mapper/pve-root" /proc/mounts && blkid /dev/pve/root | grep -qi 'TYPE="xfs"'; then
        __info__ "Detected xfs filesystem, using xfs_growfs"
        if xfs_growfs / 2>&1; then
            __ok__ "Filesystem resized"
        else
            __err__ "Failed to resize filesystem"
            exit 1
        fi
    else
        __warn__ "Unable to determine filesystem type"
        __info__ "Please resize filesystem manually if needed"
    fi

    echo
    __ok__ "local-lvm removed and root volume expanded successfully!"
    __info__ "Verify with: vgs ; lvs ; df -h"

    __prompt_keep_installed_packages__
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
