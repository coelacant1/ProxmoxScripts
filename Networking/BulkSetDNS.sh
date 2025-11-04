#!/bin/bash
#
# BulkSetDNS.sh
#
# Sets DNS servers and search domain for all nodes in Proxmox cluster.
#
# Usage:
#   BulkSetDNS.sh <dns1> <dns2> <search_domain>
#
# Arguments:
#   dns1 - Primary DNS server
#   dns2 - Secondary DNS server
#   search_domain - DNS search domain
#
# Examples:
#   BulkSetDNS.sh 8.8.8.8 8.8.4.4 mydomain.local
#   BulkSetDNS.sh 1.1.1.1 1.0.0.1 example.com
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Queries.sh
source "${UTILITYPATH}/Queries.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__

    if [[ $# -lt 3 ]]; then
        __err__ "Missing required arguments"
        echo "Usage: $0 <dns1> <dns2> <search_domain>"
        exit 64
    fi

    local dns1="$1"
    local dns2="$2"
    local search_domain="$3"

    __info__ "Setting DNS cluster-wide"
    __info__ "  DNS1: $dns1"
    __info__ "  DNS2: $dns2"
    __info__ "  Search domain: $search_domain"

    # Get remote node IPs
    local -a remote_nodes
    mapfile -t remote_nodes < <(__get_remote_node_ips__)

    local success=0
    local failed=0

    # Update DNS on remote nodes
    for node_ip in "${remote_nodes[@]}"; do
        __update__ "Setting DNS on $node_ip"
        if ssh -o StrictHostKeyChecking=no "root@${node_ip}" \
            "echo -e 'search ${search_domain}\nnameserver ${dns1}\nnameserver ${dns2}' > /etc/resolv.conf" 2>&1; then
            __ok__ "DNS configured on $node_ip"
            ((success++))
        else
            __warn__ "Failed to configure DNS on $node_ip"
            ((failed++))
        fi
    done

    # Update DNS on local node
    __update__ "Setting DNS on local node"
    if echo -e "search ${search_domain}\nnameserver ${dns1}\nnameserver ${dns2}" > /etc/resolv.conf 2>&1; then
        __ok__ "DNS configured on local node"
        ((success++))
    else
        __warn__ "Failed to configure DNS on local node"
        ((failed++))
    fi

    echo
    __info__ "DNS Configuration Summary:"
    __info__ "  Successful: $success"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: $failed" || __info__ "  Failed: $failed"

    [[ $failed -gt 0 ]] && exit 1
    __ok__ "DNS configured on all nodes!"
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
