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

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "cluster_name:string mon_ip:ip" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Check if host is already part of a cluster
    if [[ -f "/etc/pve/.members" ]]; then
        __warn__ "Existing cluster config detected (/etc/pve/.members)"
        __warn__ "Creating a new cluster may cause conflicts"
        if ! __prompt_user_yn__ "Continue anyway?"; then
            __info__ "Operation cancelled"
            exit 0
        fi
    fi

    __info__ "Creating new Proxmox cluster: ${CLUSTER_NAME}"
    __info__ "Using link0 address: ${MON_IP}"

    if pvecm create "${CLUSTER_NAME}" --link0 "address=${MON_IP}" 2>&1; then
        __ok__ "Cluster ${CLUSTER_NAME} created successfully!"
        echo
        __info__ "Verify with: pvecm status"
        __info__ "To join other nodes: pvecm add ${MON_IP}"
    else
        __err__ "Failed to create cluster"
        exit 1
    fi
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Updated to use ArgumentParser.sh
#   - Pending validation
