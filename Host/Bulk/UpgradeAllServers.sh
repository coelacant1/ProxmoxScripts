#!/bin/bash
#
# UpgradeAllServers.sh
#
# Updates all servers in the Proxmox cluster with apt-get dist-upgrade.
#
# Usage:
#   UpgradeAllServers.sh
#
# Examples:
#   UpgradeAllServers.sh
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__

    __info__ "Upgrading all servers (cluster-wide)"
    __warn__ "This may take several minutes per node"

    # Get all node IPs
    local local_node_ip
    local_node_ip=$(hostname -I | awk '{print $1}')
    local -a remote_node_ips
    mapfile -t remote_node_ips < <(__get_remote_node_ips__)
    local -a all_node_ips=("$local_node_ip" "${remote_node_ips[@]}")

    local success=0
    local failed=0

    # Update all nodes
    for node_ip in "${all_node_ips[@]}"; do
        __update__ "Upgrading node ${node_ip}"

        if [[ "${node_ip}" == "${local_node_ip}" ]]; then
            if apt-get update -qq && apt-get -y dist-upgrade 2>&1; then
                __ok__ "Local node upgraded"
                success=$((success + 1))
            else
                __warn__ "Failed to upgrade local node"
                failed=$((failed + 1))
            fi
        else
            if ssh "root@${node_ip}" "apt-get update -qq && apt-get -y dist-upgrade" 2>&1; then
                __ok__ "Node ${node_ip} upgraded"
                success=$((success + 1))
            else
                __warn__ "Failed to upgrade node ${node_ip}"
                failed=$((failed + 1))
            fi
        fi
    done

    echo
    __info__ "Cluster Upgrade Summary:"
    __info__ "  Successful: ${success}"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: ${failed}" || __info__ "  Failed: ${failed}"

    [[ $failed -gt 0 ]] && exit 1
    __ok__ "All servers upgraded successfully!"
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
#
# Fixes:
# -
#
# Known issues:
# - Pending validation
#

