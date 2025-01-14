#!/bin/bash
#
# ExpandEXT4Partition.sh
#
# Non-interactive GPT fix + partition resize + ext4 resize using sgdisk + sfdisk,
# ensuring we don't exceed the "last usable sector."
#
# Usage:
#   ./ExpandEXT4Partition.sh /dev/sdb
#
# Prerequisites/Assumptions:
#   1) The disk is GPT-labeled, has exactly one partition (/dev/sdb1).
#   2) It's ext4.
#   3) The partition is not root or LVM.
#   4) You have backups of your data.
#   5) The partition can be unmounted (e.g. not in active use).
#
# Example:
#   # Resize /dev/sdb to maximum capacity
#   ./ExpandEXT4Partition.sh /dev/sdb
#

source "$UTILITIES"

###############################################################################
# Ensure script runs as root on a Proxmox system; install needed packages.
###############################################################################
check_root
check_proxmox

install_or_prompt "gdisk"           # Provides sgdisk
install_or_prompt "parted"
install_or_prompt "util-linux"      # Ensures sfdisk, partprobe, etc. are present
install_or_prompt "e2fsprogs"       # Ensures e2fsck and resize2fs are present
install_or_prompt "uuid-runtime"    # Ensures uuidgen is present

prompt_keep_installed_packages

set -euo pipefail

###############################################################################
# Check arguments
###############################################################################
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /dev/sdX"
  exit 1
fi

DISK="$1"
PARTITION="${DISK}1"

###############################################################################
# Verify block device
###############################################################################
if [[ ! -b "$DISK" ]]; then
  echo "ERROR: \"$DISK\" is not a valid block device."
  exit 1
fi

###############################################################################
# Fix GPT with sgdisk -e (if needed), then probe
###############################################################################
echo "===> Step: Fix GPT with sgdisk -e (if needed)."
sgdisk -e "$DISK" || true
partprobe "$DISK" || true
sleep 2

###############################################################################
# Check that there is exactly one partition
###############################################################################
PART_COUNT=$(lsblk -no NAME "$DISK" | grep -c "^$(basename "$DISK")")
if [[ "$PART_COUNT" -ne 1 ]]; then
  echo "ERROR: Expected exactly 1 partition on \"$DISK\", found \"$PART_COUNT\"."
  exit 1
fi

###############################################################################
# Unmount if currently mounted
###############################################################################
MOUNTPOINT="$(lsblk -no MOUNTPOINT "$PARTITION" || true)"
if [[ -n "$MOUNTPOINT" ]]; then
  echo "Partition \"$PARTITION\" is currently mounted at \"$MOUNTPOINT\". Unmounting..."
  umount "$PARTITION" || {
    echo "ERROR: Could not unmount \"$PARTITION\". A process may still be using it."
    exit 1
  }
fi

###############################################################################
# Determine the last usable sector from sgdisk -p
###############################################################################
SGDISK_OUT="$(sgdisk -p "$DISK" || true)"
LAST_USABLE=$(echo "$SGDISK_OUT" | sed -nE 's/.*last usable sector is ([0-9]+).*/\1/p')

if [[ -z "$LAST_USABLE" ]]; then
  echo "ERROR: Could not parse last usable sector from sgdisk output:"
  echo "$SGDISK_OUT"
  exit 1
fi

echo "Last usable GPT sector on \"$DISK\" = \"$LAST_USABLE\""

###############################################################################
# Use sfdisk --dump to read the partition's start sector
###############################################################################
echo "===> Step: Reading partition info from sfdisk --dump..."
SF_OUT="$(sfdisk --dump "$DISK")"

PART_INFO="$(echo "$SF_OUT" | grep -E "^${PARTITION} :")"
if [[ -z "$PART_INFO" ]]; then
  echo "ERROR: Could not find \"${PARTITION} :\" in sfdisk dump."
  echo "sfdisk --dump output was:"
  echo "$SF_OUT"
  exit 1
fi

START_SECTOR="$(echo "$PART_INFO" | sed -nE 's/.*start= *([0-9]+).*/\1/p')"
if [[ -z "$START_SECTOR" ]]; then
  echo "ERROR: Unable to parse start sector from partition info."
  exit 1
fi

echo "Partition start sector = \"$START_SECTOR\""

###############################################################################
# Calculate new partition size in sectors
###############################################################################
NEW_SIZE=$(( LAST_USABLE - START_SECTOR + 1 ))
if (( NEW_SIZE < 1 )); then
  echo "ERROR: Computed new_size < 1, something is wrong."
  exit 1
fi

echo "New partition size     = \"$NEW_SIZE\" (in sectors)"

###############################################################################
# Create an sfdisk input to rewrite partition #1 from START_SECTOR for NEW_SIZE
###############################################################################
TMPFILE="$(mktemp)"
cat <<EOF > "$TMPFILE"
label: gpt
label-id: $(uuidgen)
device: $DISK
unit: sectors

${PARTITION} : start=${START_SECTOR}, size=${NEW_SIZE}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF

echo "===> Step: Applying new partition layout with sfdisk..."
sfdisk --no-reread --force "$DISK" < "$TMPFILE"
rm -f "$TMPFILE"

partprobe "$DISK" || true
sleep 2

###############################################################################
# Run e2fsck, then resize2fs
###############################################################################
echo "===> Step: Running e2fsck..."
e2fsck -f -y "$PARTITION"

echo "===> Step: Resizing ext4 filesystem..."
resize2fs "$PARTITION"

###############################################################################
# Remount if it was mounted before
###############################################################################
if [[ -n "$MOUNTPOINT" ]]; then
  echo "===> Step: Remounting \"$PARTITION\" at \"$MOUNTPOINT\"..."
  mkdir -p "$MOUNTPOINT" 2>/dev/null || true
  mount "$PARTITION" "$MOUNTPOINT"
fi

###############################################################################
# Show final partition table
###############################################################################
echo "===> Final partition table for \"$DISK\":"
parted -s "$DISK" print || true

echo "Resize completed successfully!"
echo "Use 'lsblk' or 'df -h' to confirm the expanded space."
