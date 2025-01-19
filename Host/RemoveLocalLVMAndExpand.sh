#!/bin/bash
#
# RemoveLocalLVMAndExpand.sh
#
# A script to remove the local-lvm volume (pve/data) on a Proxmox host and
# expand the remaining root LVM volume to use all free space, WITHOUT removing
# the 'local-lvm' entry from the Datacenter's Storage view. This allows you
# to keep the storage definition in the Proxmox configuration for future use
# or references, but still reclaim space from pve/data.
#
# WARNING:
#   - This is a DESTRUCTIVE operation. It completely removes the 'local-lvm'
#     logical volume pve/data and all data on it.
#   - Ensure you have backups for any VMs or containers stored on 'local-lvm'
#     before proceeding.
#   - This script assumes a default Proxmox installation with an LVM volume
#     group named 'pve' that contains 'pve/root' (for the OS) and 'pve/data'
#     (for local-lvm). The root partition is ext4 or xfs, and the physical disk
#     partition is already sized to your entire disk so LVM can see free extents.
#     If needed, resize your disk partition manually before running this script.
#
# Usage:
#   ./RemoveLocalLVMAndExpand.sh
#
# Example:
#   # As root, simply run:
#   ./RemoveLocalLVMAndExpand.sh
#   # Confirm the prompt to remove local-lvm, and the script will expand pve/root
#   # to occupy the freed space.
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# MAIN
###############################################################################
__check_root__         # Ensure script is run as root
__check_proxmox__      # Ensure environment is a Proxmox node

# Ensure required commands are installed (if not, user is prompted to install)
__install_or_prompt__ "lvremove"
__install_or_prompt__ "lvextend"
__install_or_prompt__ "e2fsprogs"
__install_or_prompt__ "xfsprogs"

echo "WARNING: This script will remove 'local-lvm' (pve/data) and all data on it."
echo "Ensure you have backups for any VM/container volumes stored on 'local-lvm'."
echo
read -rp "Are you sure you want to continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo "Removing the logical volume 'pve/data'..."
if lvdisplay /dev/pve/data &>/dev/null; then
  lvremove -f /dev/pve/data
  echo " - 'pve/data' removed."
else
  echo " - 'pve/data' not found or already removed."
fi

if lvdisplay /dev/pve/root &>/dev/null; then
  echo "Expanding 'pve/root' to use all free space in VG 'pve'..."
  lvextend -l +100%FREE /dev/pve/root
  echo " - 'pve/root' has been extended."
else
  echo "Warning: 'pve/root' not found. Make sure your system uses the expected LVM layout."
  __prompt_keep_installed_packages__
  exit 0
fi

# Resize the filesystem on /dev/pve/root
if grep -qs "/dev/mapper/pve-root" /proc/mounts && blkid /dev/pve/root | grep -qi 'TYPE="ext4"'; then
  echo "Detected ext4 filesystem on '/dev/pve/root'. Resizing with 'resize2fs'..."
  resize2fs /dev/pve/root
  echo " - Filesystem resized."
elif grep -qs "/dev/mapper/pve-root" /proc/mounts && blkid /dev/pve/root | grep -qi 'TYPE="xfs"'; then
  echo "Detected xfs filesystem on '/dev/pve/root'. Resizing with 'xfs_growfs'..."
  xfs_growfs /
  echo " - Filesystem resized."
else
  echo "Unable to determine filesystem type or mount for '/dev/pve/root'."
  echo "If you have a different filesystem, please resize manually."
fi

echo
echo "=== Done ==="
echo "Local-lvm ('pve/data') has been removed from LVM, and '/dev/pve/root' is expanded."
echo "The 'local-lvm' entry may still appear under Datacenter -> Storage, but it no longer exists on disk."
echo "Verify by running:  vgs ; lvs ; df -h"
echo

__prompt_keep_installed_packages__

###############################################################################
# Testing status
###############################################################################
# Tested single-node
