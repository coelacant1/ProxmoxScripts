#!/bin/bash
#
# UpdateStaleMount.sh
#
# This script updates a stale file mount across a Proxmox VE cluster by:
#   1) Disabling the specified data center storage.
#   2) Forcibly unmounting the stale mount on each cluster node.
#   3) Removing the stale directory.
#   4) Re-enabling the data center storage.
#
# Usage:
#   ./UpdateStaleMount.sh <storage_name> <mount_path>
#
# Arguments:
#   storage_name - The name/ID of the Proxmox storage to disable/re-enable.
#   mount_path   - The path of the stale mount point on each node (e.g., /mnt/pve/ISO).
#
# Example:
#   ./UpdateStaleMount.sh ISO_Storage /mnt/pve/ISO
#
source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

__check_root__
__check_proxmox__
__check_cluster_membership__

###############################################################################
# Parse and validate arguments
###############################################################################
STORAGE_NAME="$1"
MOUNT_PATH="$2"

if [ -z "$STORAGE_NAME" ] || [ -z "$MOUNT_PATH" ]; then
  echo "Usage: $0 <storage_name> <mount_path>"
  exit 1
fi

###############################################################################
# Step 1: Disable the data center storage
###############################################################################
echo "Disabling storage \"${STORAGE_NAME}\"..."
pvesm set "${STORAGE_NAME}" --disable 1
if [ $? -ne 0 ]; then
  echo "Error: Failed to disable storage \"${STORAGE_NAME}\"."
  exit 1
fi

###############################################################################
# Step 2: Gather cluster node IPs
###############################################################################
echo "Retrieving remote node IPs..."
readarray -t REMOTE_NODE_IPS < <( __get_remote_node_ips__ )
if [ ${#REMOTE_NODE_IPS[@]} -eq 0 ]; then
  echo "Error: No remote node IPs found. Ensure this node is part of a cluster."
  exit 1
fi

echo "Found the following node IPs in the cluster:"
printf '%s\n' "${REMOTE_NODE_IPS[@]}"

###############################################################################
# Step 3: Unmount and remove the stale directory on each node
###############################################################################
for nodeIp in "${REMOTE_NODE_IPS[@]}"; do
  echo "Processing node IP: \"${nodeIp}\""
  ssh root@"${nodeIp}" "umount -f \"${MOUNT_PATH}\"" 2>/dev/null
  ssh root@"${nodeIp}" "rm -rf \"${MOUNT_PATH}\"" 2>/dev/null
done

###############################################################################
# Step 4: Re-enable the storage
###############################################################################
echo "Re-enabling storage \"${STORAGE_NAME}\"..."
pvesm set "${STORAGE_NAME}" --disable 0
if [ $? -ne 0 ]; then
  echo "Error: Failed to re-enable storage \"${STORAGE_NAME}\"."
  exit 1
fi

echo "Successfully updated the stale file mount for storage \"${STORAGE_NAME}\"."
exit 0
