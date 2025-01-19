#!/bin/bash
#
# SeparateNode.sh
#
# This script forcibly removes the current node from a Proxmox cluster.
#
# Usage:
#   ./SeparateNode.sh
#
# Note:
#   After removing the node from the cluster, it will still have access
#   to any shared storage. Ensure you set up separate storage for this
#   node and move all data/VMs before detaching from the cluster, as
#   shared storage cannot be safely used across cluster boundaries.
#

###############################################################################
# Pre-flight Checks
###############################################################################
source "${UTILITYPATH}/Prompts.sh"
__check_root__
__check_proxmox__

###############################################################################
# Confirmation Prompt
###############################################################################
echo "WARNING: This action will forcibly remove the node from the cluster."
read -r -p "Are you sure you want to proceed? [y/N]: " userResponse
case "$userResponse" in
    [yY]|[yY][eE][sS])
        echo "Proceeding with node removal..."
        ;;
    *)
        echo "Aborting node removal."
        exit 0
        ;;
esac

###############################################################################
# Stop Cluster Services
###############################################################################
echo "Stopping cluster services..."
systemctl stop pve-cluster
systemctl stop corosync

###############################################################################
# Unmount the pmxcfs filesystem (if still running) and remove Corosync config
###############################################################################
echo "Unmounting pmxcfs (if active) and removing Corosync configuration..."
pmxcfs -l
rm /etc/pve/corosync.conf
rm -r /etc/corosync/*

###############################################################################
# Kill pmxcfs process if still active
###############################################################################
echo "Killing pmxcfs if still active..."
killall pmxcfs

###############################################################################
# Restart pve-cluster and set cluster expectation to single node
###############################################################################
echo "Restarting pve-cluster and setting expected cluster size to 1..."
systemctl start pve-cluster
pvecm expected 1

###############################################################################
# Remove Corosync data
###############################################################################
echo "Removing Corosync data..."
rm /var/lib/corosync/*

echo "Node has been forcibly removed from the cluster."
echo "Make sure no shared storage is still in use by multiple clusters."

###############################################################################
# Testing status
###############################################################################
# Tested single-node
