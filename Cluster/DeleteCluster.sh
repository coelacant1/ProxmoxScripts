#!/bin/bash
#
# DeleteCluster.sh
#
# Removes cluster configuration from a single-node Proxmox cluster,
# returning the node to standalone mode.
#
# Usage:
#   DeleteCluster.sh [--force]
#
# Examples:
#   DeleteCluster.sh
#   DeleteCluster.sh --force    # Skip confirmation
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

# Parse --force flag
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=1
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: DeleteCluster.sh [--force]"
            exit 64
            ;;
    esac
done

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __warn__ "DESTRUCTIVE: This will remove cluster configuration from this node"
    __warn__ "This operation cannot be undone"
    
    # Safety check: Require --force in non-interactive mode
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]] && [[ $FORCE -eq 0 ]]; then
        __err__ "Destructive operation requires --force flag in non-interactive mode"
        __err__ "Usage: DeleteCluster.sh --force"
        __err__ "Or add '--force' to parameters in GUI"
        exit 1
    fi

    # Prompt for confirmation (unless force is set)
    if [[ $FORCE -eq 1 ]]; then
        __info__ "Force mode enabled - proceeding without confirmation"
    elif ! __prompt_user_yn__ "Proceed with cluster removal?"; then
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
