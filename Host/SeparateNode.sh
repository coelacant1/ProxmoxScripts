#!/bin/bash
#
# SeparateNode.sh
#
# Forcibly removes the current node from a Proxmox cluster.
# WARNING: Shared storage may still be accessible. Migrate VMs/data first.
#
# Usage:
#   SeparateNode.sh
#
# Examples:
#   SeparateNode.sh
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

    __warn__ "This will forcibly remove the node from the cluster"
    __warn__ "Shared storage will still be accessible - migrate VMs/data first"

    if ! __prompt_yes_no__ "Proceed with node separation?"; then
        __info__ "Operation cancelled"
        exit 0
    fi

    # Stop cluster services
    __info__ "Stopping cluster services"
    systemctl stop pve-cluster 2>/dev/null || true
    systemctl stop corosync 2>/dev/null || true
    __ok__ "Cluster services stopped"

    # Unmount pmxcfs and remove corosync config
    __info__ "Unmounting pmxcfs and removing Corosync configuration"
    pmxcfs -l 2>/dev/null || true
    rm -f /etc/pve/corosync.conf 2>/dev/null || true
    rm -rf /etc/corosync/* 2>/dev/null || true
    __ok__ "Corosync configuration removed"

    # Kill pmxcfs if still active
    __info__ "Stopping pmxcfs process"
    killall pmxcfs 2>/dev/null || true
    __ok__ "pmxcfs stopped"

    # Restart pve-cluster as standalone
    __info__ "Restarting pve-cluster in standalone mode"
    systemctl start pve-cluster 2>/dev/null || true
    sleep 2
    pvecm expected 1 2>/dev/null || true
    __ok__ "pve-cluster restarted"

    # Remove Corosync data
    __info__ "Removing Corosync data"
    rm -f /var/lib/corosync/* 2>/dev/null || true
    __ok__ "Corosync data removed"

    echo
    __ok__ "Node forcibly removed from cluster successfully!"
    __warn__ "Ensure shared storage is no longer accessed by multiple clusters"
    __info__ "Verify with: pvecm status"
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
