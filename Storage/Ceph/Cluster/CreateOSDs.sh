#!/bin/bash
#
# CephCreateOSDsAllNodes.sh
#
# This script runs on all nodes in the Proxmox cluster to automatically create 
# Ceph OSDs on all unused block devices (e.g., /dev/sd*, /dev/nvme*, /dev/hd*).
#
# Usage:
#   ./CephCreateOSDsAllNodes.sh
#
# Requirements/Assumptions:
#   1. Passwordless SSH or valid SSH keys for root on all nodes.
#   2. Each node is in a functioning Proxmox cluster (pvecm available).
#   3. Each node has Ceph installed and configured sufficiently to run 'ceph-volume'.
#   4. Devices that need to be skipped are either already mounted or in pvs.
#
# Function Index:
#   - create_osds
#
source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

__check_root__
__check_proxmox__
__check_cluster_membership__

###############################################################################
# FUNCTION: create_osds
# Iterates over block devices (/dev/sd*, /dev/nvme*, /dev/hd*) and:
#   - Checks if the device is valid (-b)
#   - Ensures the device is unused (not mounted, not in pvs)
#   - Creates a Ceph OSD via ceph-volume
###############################################################################
create_osds() {
  echo "=== Checking for devices on node: $(hostname) ==="
  for device in /dev/sd* /dev/nvme* /dev/hd* 2>/dev/null; do
    [ -e "$device" ] || continue
    if [ -b "$device" ]; then
      if lsblk -no MOUNTPOINT "$device" | grep -q '^$' && ! pvs 2>/dev/null | grep -q "$device"; then
        echo "Creating OSD for \"$device\"..."
        if ceph-volume lvm create --data "$device"; then
          echo "Successfully created OSD for \"$device\"."
        else
          echo "Failed to create OSD for \"$device\". Continuing..."
        fi
      else
        echo "\"$device\" is in use (mounted or in pvs). Skipping."
      fi
    else
      echo "\"$device\" is not a valid block device. Skipping."
    fi
  done
  echo "=== OSD creation complete on node: $(hostname) ==="
}

###############################################################################
# MAIN SCRIPT
###############################################################################
echo "=== Starting OSD creation on all nodes ==="

readarray -t REMOTE_NODES < <( __get_remote_node_ips__ )
if [ "${#REMOTE_NODES[@]}" -eq 0 ]; then
  echo "Error: No remote nodes found in the cluster."
  exit 1
fi

for NODE_IP in "${REMOTE_NODES[@]}"; do
  echo "=> Connecting to node: \"$NODE_IP\""
  ssh root@"$NODE_IP" "$(typeset -f create_osds); create_osds"
done

echo "=== Ceph OSD creation process completed on all nodes! ==="
