#!/bin/bash
#
# DiskDeleteWithSnapshot.sh
#
# This script manages snapshots and disk images within a Ceph storage pool.
# It checks for a particular snapshot named "__base__" and, if it is the only snapshot,
# unprotects and deletes it before removing the associated disk. This is useful for
# cleaning up after rollback operations or freeing space from unused snapshots/disks.
#
# Usage:
#   ./DiskDeleteWithSnapshot.sh <pool_name> <disk_name>
#     <pool_name> - The name of the Ceph pool where the disk is located.
#     <disk_name> - The name of the disk image to check and potentially delete.
#
# Example:
#   # Deletes the disk 'my-disk' in the 'mypool' pool if only the __base__ snapshot exists:
#   ./DiskDeleteWithSnapshot.sh mypool my-disk
#
# Function Index:
#   - deleteSnapshot
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Environment Checks
###############################################################################
__check_root__
__check_proxmox__

###############################################################################
# Main Function
###############################################################################
function deleteSnapshot() {
  local poolName="$1"
  local diskName="$2"

  echo "Listing snapshots for \"${poolName}/${diskName}\"..."

  # Get the snapshot list
  local snapshotList
  snapshotList=$(rbd snap ls "${poolName}/${diskName}")
  if [ "$?" -ne 0 ]; then
    echo "Error: Failed to list snapshots for \"${poolName}/${diskName}\"."
    return 1
  fi

  echo "Snapshot list:"
  echo "${snapshotList}"

  # Check if __base__ is the only snapshot
  local totalSnapshots
  totalSnapshots=$(echo "${snapshotList}" | grep -v "NAME" | wc -l)

  if echo "${snapshotList}" | grep -q "__base__" && [ "${totalSnapshots}" -eq 1 ]; then
    echo "Only \"__base__\" snapshot found. Proceeding with deletion..."

    # Unprotect the snapshot
    rbd snap unprotect "${poolName}/${diskName}@__base__"
    if [ "$?" -ne 0 ]; then
      echo "Error: Failed to unprotect the snapshot \"${poolName}/${diskName}@__base__\"."
      return 1
    fi

    # Delete the snapshot
    rbd snap rm "${poolName}/${diskName}@__base__"
    if [ "$?" -ne 0 ]; then
      echo "Error: Failed to remove the snapshot \"${poolName}/${diskName}@__base__\"."
      return 1
    fi

    # Remove the disk
    rbd rm "${diskName}" -p "${poolName}"
    if [ "$?" -ne 0 ]; then
      echo "Error: Failed to remove the disk \"${diskName}\" in pool \"${poolName}\"."
      return 1
    fi

    echo "\"__base__\" snapshot and disk \"${diskName}\" have been deleted."
  else
    echo "Other snapshots exist or \"__base__\" is not the only snapshot. No action taken."
  fi
}

###############################################################################
# Argument Validation
###############################################################################
POOL_NAME="$1"
DISK_NAME="$2"

if [ -z "${POOL_NAME}" ] || [ -z "${DISK_NAME}" ]; then
  echo "Usage: $0 <pool_name> <disk_name>"
  exit 1
fi

###############################################################################
# Execution
###############################################################################
deleteSnapshot "${POOL_NAME}" "${DISK_NAME}"
