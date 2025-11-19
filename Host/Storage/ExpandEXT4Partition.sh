#!/bin/bash
#
# ExpandEXT4Partition.sh
#
# Expands a GPT partition and ext4 filesystem to use available disk space.
# Non-interactive operation using sgdisk and sfdisk.
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
    __install_or_prompt__ "uuid-runtime"

    local partition="${DEVICE}1"

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

    # Verify exactly one partition
    local part_count
    part_count=$(lsblk -no NAME "$DEVICE" | grep -c "^$(basename "$DEVICE")" || echo 0)
    if [[ "$part_count" -ne 1 ]]; then
        __err__ "Expected exactly 1 partition, found $part_count"
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

    # Get last usable sector
    __info__ "Determining disk geometry"
    local sgdisk_out
    sgdisk_out=$(sgdisk -p "$DEVICE" 2>&1 || true)
    local last_usable
    last_usable=$(echo "$sgdisk_out" | sed -nE 's/.*last usable sector is ([0-9]+).*/\1/p')

    if [[ -z "$last_usable" ]]; then
        __err__ "Could not determine last usable sector"
        exit 1
    fi

    __info__ "Last usable sector: $last_usable"

    # Get partition start sector
    local sf_out
    sf_out=$(sfdisk --dump "$DEVICE" 2>&1)
    local part_info
    part_info=$(echo "$sf_out" | grep -E "^${partition} :")

    if [[ -z "$part_info" ]]; then
        __err__ "Could not find partition info"
        exit 1
    fi

    local start_sector
    start_sector=$(echo "$part_info" | sed -nE 's/.*start= *([0-9]+).*/\1/p')

    if [[ -z "$start_sector" ]]; then
        __err__ "Could not determine start sector"
        exit 1
    fi

    __info__ "Start sector: $start_sector"

    # Calculate new size
    local new_size=$((last_usable - start_sector + 1))
    if ((new_size < 1)); then
        __err__ "Invalid partition size calculated"
        exit 1
    fi

    __info__ "New partition size: $new_size sectors"

    # Create sfdisk input
    local tmpfile
    tmpfile=$(mktemp)
    cat <<EOF >"$tmpfile"
label: gpt
label-id: $(uuidgen)
device: $DEVICE
unit: sectors

${partition} : start=${start_sector}, size=${new_size}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF

    __info__ "Applying new partition layout"
    if sfdisk --no-reread --force "$DEVICE" <"$tmpfile" 2>&1; then
        __ok__ "Partition table updated"
    else
        __err__ "Failed to update partition table"
        rm -f "$tmpfile"
        exit 1
    fi
    rm -f "$tmpfile"

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

# Testing status:
#   - Updated to use utility functions
#   - Updated to use ArgumentParser.sh
#   - Pending validation
