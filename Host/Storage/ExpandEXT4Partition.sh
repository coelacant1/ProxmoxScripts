#!/bin/bash
#
# ExpandEXT4Partition.sh
#
# Expands a GPT partition and ext4 filesystem to use available disk space.
# Uses parted for safe in-place partition resizing without destroying metadata.
#
# Usage:
#   ExpandEXT4Partition.sh <device>
#
# Arguments:
#   device - Disk device (e.g., /dev/sdb)
#
# Examples:
#   ExpandEXT4Partition.sh /dev/sdb
#
# Function Index:
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

__parse_args__ "device:path" "$@"

# Verify block device
if [[ ! -b "$DEVICE" ]]; then
    __err__ "Not a valid block device: $DEVICE"
    exit 1
fi

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __install_or_prompt__ "gdisk"
    __install_or_prompt__ "parted"
    __install_or_prompt__ "util-linux"
    __install_or_prompt__ "e2fsprogs"

    # Construct partition device name (handle nvme/mmcblk naming)
    local partition
    if [[ "$DEVICE" =~ (nvme|mmcblk|loop) ]]; then
        partition="${DEVICE}p1"
    else
        partition="${DEVICE}1"
    fi

    __warn__ "This will resize partition ${partition} to use all available space"
    __warn__ "Ensure you have backups before proceeding"

    if ! __prompt_user_yn__ "Proceed with partition expansion?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    # Fix GPT if needed
    __info__ "Fixing GPT table if needed"
    sgdisk -e "$DEVICE" 2>&1 || true
    partprobe "$DEVICE" 2>&1 || true
    sleep 2

    # Verify exactly one partition exists
    local part_count
    part_count=$(lsblk -no NAME "$DEVICE" | grep -c "[0-9]$" || echo 0)
    if [[ "$part_count" -ne 1 ]]; then
        __err__ "Expected exactly 1 partition on device, found $part_count"
        __err__ "This script only supports single-partition devices"
        exit 1
    fi

    # Unmount if mounted
    local mountpoint
    mountpoint=$(lsblk -no MOUNTPOINT "$partition" 2>/dev/null || true)
    if [[ -n "$mountpoint" ]]; then
        __info__ "Unmounting ${partition} from ${mountpoint}"
        if umount "$partition" 2>&1; then
            __ok__ "Unmounted successfully"
        else
            __err__ "Could not unmount ${partition}"
            exit 1
        fi
    fi

    # Use parted to resize partition in-place (safer than recreating table)
    __info__ "Resizing partition to use all available space"
    if parted "$DEVICE" ---pretend-input-tty <<EOF 2>&1
resizepart 1 100%
Yes
EOF
    then
        __ok__ "Partition resized successfully"
    else
        __err__ "Failed to resize partition"
        exit 1
    fi

    partprobe "$DEVICE" 2>&1 || true
    sleep 2

    # Run e2fsck
    __info__ "Checking filesystem"
    if e2fsck -f -y "$partition" 2>&1; then
        __ok__ "Filesystem check completed"
    else
        __warn__ "Filesystem check reported issues"
    fi

    # Resize filesystem
    __info__ "Resizing ext4 filesystem"
    if resize2fs "$partition" 2>&1; then
        __ok__ "Filesystem resized"
    else
        __err__ "Failed to resize filesystem"
        exit 1
    fi

    # Remount if it was mounted
    if [[ -n "$mountpoint" ]]; then
        __info__ "Remounting at $mountpoint"
        mkdir -p "$mountpoint" 2>/dev/null || true
        if mount "$partition" "$mountpoint" 2>&1; then
            __ok__ "Remounted successfully"
        else
            __warn__ "Could not remount partition"
        fi
    fi

    echo
    __ok__ "Partition expansion completed successfully!"
    __info__ "Verify with: lsblk or df -h"

    __prompt_keep_installed_packages__
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: Pending validation
# - 2025-11-20: Updated to use ArgumentParser.sh
# - 2025-11-20: Added proper nvme/mmcblk partition naming support
# - 2025-11-20: Validated against CONTRIBUTING.md
# - Non-interactive operation using sgdisk and sfdisk (note: now uses parted)
#
# Fixes:
# - 2025-11-20: Fixed partition count logic (was counting device + partitions)
# - 2025-11-20: Fixed to use parted resizepart instead of recreating partition table
#
# Known issues:
# - Pending validation
#

