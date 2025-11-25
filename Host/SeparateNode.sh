#!/bin/bash
#
# SeparateNode.sh
#
# Forcibly removes the current node from a Proxmox cluster.
# WARNING: Shared storage may still be accessible. Migrate VMs/data first.
#
# Usage:
#   SeparateNode.sh [--force]
#
# Examples:
#   SeparateNode.sh
#   SeparateNode.sh --force    # Skip confirmation
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
            echo "Usage: SeparateNode.sh [--force]"
            exit 64
            ;;
    esac
done

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __warn__ "DESTRUCTIVE: This will forcibly remove the node from the cluster"
    __warn__ "Shared storage will still be accessible - migrate VMs/data first"

    # Safety check: Require --force in non-interactive mode
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]] && [[ $FORCE -eq 0 ]]; then
        __err__ "Destructive operation requires --force flag in non-interactive mode"
        __err__ "Usage: SeparateNode.sh --force"
        __err__ "Or add '--force' to parameters in GUI"
        exit 1
    fi

    # Prompt for confirmation (unless force is set)
    if [[ $FORCE -eq 1 ]]; then
        __info__ "Force mode enabled - proceeding without confirmation"
    elif ! __prompt_user_yn__ "Proceed with node separation?"; then
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

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: Pending validation
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# - Pending validation
# -
#

