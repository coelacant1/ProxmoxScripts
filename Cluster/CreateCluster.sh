#!/bin/bash
#
# CreateCluster.sh
#
# Creates a new Proxmox cluster on the current host.
#
# Usage:
#   CreateCluster.sh <cluster_name> <mon_ip>
#
# Arguments:
#   cluster_name - Name for the new cluster
#   mon_ip       - Management/Corosync IP for cluster communication
#
# Examples:
#   CreateCluster.sh myCluster 192.168.100.10
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

    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments"
        echo "Usage: $0 <cluster_name> <mon_ip>"
        exit 64
    fi

    local cluster_name="$1"
    local mon_ip="$2"

    # Check if host is already part of a cluster
    if [[ -f "/etc/pve/.members" ]]; then
        __warn__ "Existing cluster config detected (/etc/pve/.members)"
        __warn__ "Creating a new cluster may cause conflicts"
        if ! __prompt_yes_no__ "Continue anyway?"; then
            __info__ "Operation cancelled"
            exit 0
        fi
    fi

    __info__ "Creating new Proxmox cluster: ${cluster_name}"
    __info__ "Using link0 address: ${mon_ip}"

    if pvecm create "${cluster_name}" --link0 "address=${mon_ip}" 2>&1; then
        __ok__ "Cluster ${cluster_name} created successfully!"
        echo
        __info__ "Verify with: pvecm status"
        __info__ "To join other nodes: pvecm add ${mon_ip}"
    else
        __err__ "Failed to create cluster"
        exit 1
    fi
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
