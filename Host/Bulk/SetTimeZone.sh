#!/bin/bash
#
# SetTimeServer.sh
#
# A script to set the timezone across all nodes in a Proxmox VE cluster.
# Defaults to "America/New_York" if no argument is provided.
#
# Usage:
#   ./SetTimeServer.sh <timezone>
#
# Examples:
#   ./SetTimeServer.sh
#   ./SetTimeServer.sh "Europe/Berlin"
#
# This script will:
#   1. Check if running as root (__check_root__).
#   2. Check if on a valid Proxmox node (__check_proxmox__).
#   3. Verify the node is part of a cluster (__check_cluster_membership__).
#   4. Gather remote node IPs from __get_remote_node_ips__.
#   5. Set the specified timezone on each remote node and then on the local node.
#

source "${UTILITYPATH}/Communication.sh"
source "${UTILITYPATH}/Prompts.sh"
source "${UTILITYPATH}/Queries.sh"

###############################################################################
# Pre-flight checks
###############################################################################
__check_root__
__check_proxmox__
__check_cluster_membership__

###############################################################################
# Main
###############################################################################
TIMEZONE="${1:-America/New_York}"
echo "Selected timezone: \"${TIMEZONE}\""

# Gather IP addresses of all remote nodes
readarray -t REMOTE_NODES < <( __get_remote_node_ips__ )

# Set timezone on each remote node
for nodeIp in "${REMOTE_NODES[@]}"; do
    __info__ "Setting timezone to \"${TIMEZONE}\" on node: \"${nodeIp}\""
    if ssh "root@${nodeIp}" "timedatectl set-timezone \"${TIMEZONE}\""; then
        __ok__ " - Timezone set successfully on node: \"${nodeIp}\""
    else
        __err__ " - Failed to set timezone on node: \"${nodeIp}\""
    fi
done

# Finally, set the timezone on the local node
__info__ "Setting timezone to \"${TIMEZONE}\" on local node..."
if timedatectl set-timezone "${TIMEZONE}"; then
    __ok__ " - Timezone set successfully on local node"
else
    __err__ " - Failed to set timezone on local node"
fi

echo "Timezone setup completed for all nodes!"

###############################################################################
# Testing status
###############################################################################
# Tested single-node
# Tested multi-node
