#!/bin/bash
#
# DeleteCluster.sh
#
# Removes cluster configuration from a single-node Proxmox cluster,
# returning the node to standalone mode.
#
# Usage:
#   DeleteCluster.sh
#
# Examples:
#   DeleteCluster.sh
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __warn__ "This will remove cluster configuration from this node"
    __warn__ "This is DESTRUCTIVE and cannot be undone"

    if ! __prompt_yes_no__ "Proceed with cluster removal?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    local node_count
    node_count=$(__get_number_of_cluster_nodes__)
    if [[ "$node_count" -gt 1 ]]; then
        __err__ "This script is for single-node clusters only"
        __err__ "Current cluster has ${node_count} nodes. Remove other nodes first."
        exit 1
    fi

    __info__ "Stopping cluster services"
    systemctl stop corosync || true
    systemctl stop pve-cluster || true

    __info__ "Removing Corosync configuration"
    rm -f "/etc/pve/corosync.conf" 2>/dev/null || true
    rm -rf "/etc/corosync/"* 2>/dev/null || true

    __info__ "Restarting pve-cluster in standalone mode"
    systemctl start pve-cluster

    __info__ "Disabling corosync service"
    systemctl stop corosync 2>/dev/null || true
    systemctl disable corosync 2>/dev/null || true

    __ok__ "Cluster configuration removed successfully!"
    __info__ "This node is now standalone. Verify with: pvecm status"
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
