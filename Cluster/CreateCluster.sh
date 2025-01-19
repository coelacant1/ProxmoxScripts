#!/bin/bash
#
# CreateCluster.sh
#
# Creates a new Proxmox cluster on a single host. This script requires:
#   1) A cluster name (e.g. "MyCluster")
#   2) A management (Corosync) IP for cluster communication
#
# Usage:
#   ./CreateCluster.sh <clustername> <mon-ip>
#
# Example:
#   # Create a cluster named 'myCluster' using 192.168.100.10 as Corosync IP
#   ./CreateCluster.sh myCluster 192.168.100.10
#
# After running this script, you can join other Proxmox nodes to the cluster with:
#   pvecm add <mon-ip-of-this-node>
#

source "${UTILITYPATH}/Prompts.sh"

###############################################################################
# Checks and Setup
###############################################################################
__check_root__
__check_proxmox__

if [[ $# -lt 2 ]]; then
  echo "Error: Missing arguments."
  echo "Usage: $0 <clustername> <mon-ip>"
  exit 1
fi

CLUSTER_NAME="$1"
MON_IP="$2"

# Check if host is already part of a cluster
if [[ -f "/etc/pve/.members" ]]; then
  echo "WARNING: This host appears to have an existing cluster config (/etc/pve/.members)."
  echo "If it's already part of a cluster, creating a new one may cause conflicts."
  echo "Press Ctrl-C to abort, or wait 5 seconds to continue..."
  sleep 5
fi

###############################################################################
# Main
###############################################################################
echo "Creating new Proxmox cluster: \"${CLUSTER_NAME}\""
echo "Using IP for link0: \"${MON_IP}\""

pvecm create "${CLUSTER_NAME}" --link0 address="${MON_IP}"

echo
echo "Cluster \"${CLUSTER_NAME}\" created with link0 address set to \"${MON_IP}\"."
echo "To verify status:  pvecm status"
echo "To join another node to this cluster (from that node):"
echo "  pvecm add \"${MON_IP}\""

###############################################################################
# Testing status
###############################################################################
# Tested single-node
# Tested multi-node
