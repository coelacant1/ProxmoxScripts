#!/bin/bash
#
# DiskDeleteBulk.sh
#
# This script automates the process of deleting specific disk images from a Ceph
# storage pool. It is designed to operate over a range of virtual machine (VM)
# disk images, identifying each by a unique naming convention and deleting them
# from the specified Ceph pool. This is particularly useful for bulk cleanup of
# VM disk images in virtualized data centers or cloud platforms.
#
# Usage:
#   ./DiskDeleteBulk.sh <pool_name> <start_vm_index> <end_vm_index> <disk_number>
#
# Example:
#   ./DiskDeleteBulk.sh vm_pool 1 100 1
#
# Function Index:
#   - delete_disk
#

source "$UTILITIES"

check_root
check_proxmox

###############################################################################
# Validate and parse inputs
###############################################################################
POOL_NAME="$1"
START_VM_INDEX="$2"
END_VM_INDEX="$3"
DISK_NUMBER="$4"

if [ -z "$POOL_NAME" ] || [ -z "$START_VM_INDEX" ] || [ -z "$END_VM_INDEX" ] || [ -z "$DISK_NUMBER" ]; then
  echo "Error: Missing required arguments."
  echo "Usage: ./DiskDeleteBulk.sh <pool_name> <start_vm_index> <end_vm_index> <disk_number>"
  exit 1
fi

###############################################################################
# Delete a disk in the specified Ceph pool
###############################################################################
function delete_disk() {
  local pool="$1"
  local disk="$2"

  rbd rm "$disk" -p "$pool"
  if [ $? -ne 0 ]; then
    echo "Failed to remove the disk \"$disk\" in pool \"$pool\""
    return 1
  fi

  echo "Disk \"$disk\" has been deleted."
}

###############################################################################
# Main
###############################################################################
for vmIndex in $(seq "$START_VM_INDEX" "$END_VM_INDEX"); do
  diskName="vm-${vmIndex}-disk-${DISK_NUMBER}"
  delete_disk "$POOL_NAME" "$diskName"
done
