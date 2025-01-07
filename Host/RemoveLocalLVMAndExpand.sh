#!/bin/bash
#
# RemoveLocalLVMAndExpand.sh
#
# A script to remove the local-lvm volume (pve/data) on a Proxmox host and
# expand the remaining root LVM volume to use all free space, WITHOUT removing
# the 'local-lvm' entry from the Datacenter's Storage view (i.e., we do NOT run
# 'pvesm remove local-lvm'). This is useful if you want to keep the storage
# definition in place for future use or references, but still reclaim space
# from pve/data.
#
# WARNING:
#   - This is a DESTRUCTIVE operation. It completely removes the 'local-lvm'
#     logical volume pve/data and all data on it.
#   - Ensure you have backups for any VMs or containers stored on 'local-lvm'
#     before proceeding.
#   - This script assumes:
#       * A default Proxmox installation with an LVM volume group named 'pve'
#         containing 'pve/root' (for the OS) and 'pve/data' (for local-lvm).
#       * The root partition is ext4 or xfs.
#       * The physical disk partition is already sized to your entire disk,
#         so LVM sees the free extents. If needed, expand/resize your disk
#         partition manually before running this script.
#
# Usage:
#   1) Run as root on a Proxmox node:
#        ./RemoveLocalLVMAndExpand.sh
#   2) Confirm the prompt to proceed with removal of local-lvm (pve/data).
#   3) Upon completion, /dev/pve/root should be expanded to occupy the freed
#      space, and local-lvm is logically removed from LVM (though the entry may
#      remain in the Datacenter/Storage config).
#

set -e  # Exit immediately on error

###############################################################################
# 1. FIND AND SOURCE UTILITIES
###############################################################################
find_utilities_script() {
  # Check current directory first
  if [[ -d "./Utilities" ]]; then
    echo "./Utilities/Utilities.sh"
    return 0
  fi

  local rel_path=""
  for _ in {1..15}; do
    cd ..
    # If rel_path is empty, set it to '..' else prepend '../'
    if [[ -z "$rel_path" ]]; then
      rel_path=".."
    else
      rel_path="../$rel_path"
    fi

    if [[ -d "./Utilities" ]]; then
      echo "$rel_path/Utilities/Utilities.sh"
      return 0
    fi
  done

  echo "Error: Could not find 'Utilities' folder within 15 levels." >&2
  return 1
}

UTILITIES_DIR="$(find_utilities_script)"
# shellcheck source=/dev/null
source "${UTILITIES_DIR}/Utilities.sh"

###############################################################################
# MAIN
###############################################################################
main() {
  # --- Check basic environment -----------------------------------------------
  check_proxmox_and_root  # Must be root and on a Proxmox node

  # Ensure required LVM and filesystem tools are installed
  install_or_prompt "lvremove"
  install_or_prompt "lvextend"
  install_or_prompt "e2fsprogs"
  install_or_prompt "xfsprogs"

  echo "WARNING: This script will remove local-lvm (pve/data) and all data stored on it."
  echo "Ensure you have backups for any VM/container volumes on 'local-lvm' storage."
  echo
  read -rp "Are you sure you want to continue? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
  fi

  # --- Remove the pve/data logical volume ------------------------------------
  echo "Removing the logical volume pve/data..."
  if lvdisplay /dev/pve/data &>/dev/null; then
      lvremove -f /dev/pve/data
      echo " - pve/data removed."
  else
      echo " - pve/data not found or already removed."
  fi

  # --- Expand pve/root to use all free extents -------------------------------
  if lvdisplay /dev/pve/root &>/dev/null; then
      echo "Expanding pve/root to use all free space in VG 'pve'..."
      lvextend -l +100%FREE /dev/pve/root
      echo " - pve/root has been extended."
  else
      echo "Warning: pve/root not found. Make sure your system uses the expected LVM layout."
      prompt_keep_installed_packages
      exit 0
  fi

  # --- Resize the filesystem on pve/root -------------------------------------
  if grep -qs "/dev/mapper/pve-root" /proc/mounts && \
     blkid /dev/pve/root | grep -qi 'TYPE="ext4"'; then
      echo "Detected ext4 filesystem on /dev/pve/root. Resizing with resize2fs..."
      resize2fs /dev/pve/root
      echo " - Filesystem resized."
  elif grep -qs "/dev/mapper/pve-root" /proc/mounts && \
       blkid /dev/pve/root | grep -qi 'TYPE="xfs"'; then
      echo "Detected xfs filesystem on /dev/pve/root. Resizing with xfs_growfs..."
      xfs_growfs /
      echo " - Filesystem resized."
  else
      echo "Unable to determine filesystem type or mount for /dev/pve/root."
      echo "If you have a different filesystem, please resize manually."
  fi

  echo
  echo "=== Done ==="
  echo "local-lvm (pve/data) has been removed from LVM, and /dev/pve/root is expanded."
  echo "The 'local-lvm' entry may still appear in Datacenter -> Storage, but it no longer exists on disk."
  echo "Verify by running:  vgs ; lvs ; df -h"
  echo

  # Prompt to remove any packages installed during this session
  prompt_keep_installed_packages
}

main
