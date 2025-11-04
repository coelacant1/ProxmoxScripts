#!/bin/bash
#
# SetTimeZone.sh
#
# Sets timezone across all nodes in a Proxmox cluster.
# Defaults to "America/New_York" if no timezone specified.
#
# Usage:
#   SetTimeZone.sh [timezone]
#
# Arguments:
#   timezone - Optional timezone (default: America/New_York)
#
# Examples:
#   SetTimeZone.sh
#   SetTimeZone.sh Europe/Berlin
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__

    local timezone="${1:-America/New_York}"

    __info__ "Setting timezone: ${timezone} (cluster-wide)"

    # Get remote node IPs
    local -a remote_nodes
    mapfile -t remote_nodes < <(__get_remote_node_ips__)

    local success=0
    local failed=0

    # Set timezone on remote nodes
    for node_ip in "${remote_nodes[@]}"; do
        __update__ "Setting timezone on ${node_ip}"
        if ssh "root@${node_ip}" "timedatectl set-timezone \"${timezone}\"" 2>&1; then
            __ok__ "Timezone set on ${node_ip}"
            ((success++))
        else
            __warn__ "Failed to set timezone on ${node_ip}"
            ((failed++))
        fi
    done

    # Set timezone on local node
    __update__ "Setting timezone on local node"
    if timedatectl set-timezone "${timezone}" 2>&1; then
        __ok__ "Timezone set on local node"
        ((success++))
    else
        __warn__ "Failed to set timezone on local node"
        ((failed++))
    fi

    echo
    __info__ "Timezone Configuration Summary:"
    __info__ "  Successful: ${success}"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: ${failed}" || __info__ "  Failed: ${failed}"

    [[ $failed -gt 0 ]] && exit 1
    __ok__ "Timezone set to ${timezone} on all nodes!"
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
