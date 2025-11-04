#!/bin/bash
#
# ProxmoxEnableMicrocode.sh
#
# Enables microcode updates (Intel/AMD) on all nodes in a Proxmox cluster.
#
# Usage:
#   ProxmoxEnableMicrocode.sh
#
# Examples:
#   ProxmoxEnableMicrocode.sh
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

    __info__ "Enabling microcode updates (cluster-wide)"

    # Get remote node IPs
    local -a remote_nodes
    mapfile -t remote_nodes < <(__get_remote_node_ips__)

    local success=0
    local failed=0

    # Enable on remote nodes
    for node_ip in "${remote_nodes[@]}"; do
        __update__ "Enabling microcode on ${node_ip}"
        if ssh "root@${node_ip}" "apt-get update -qq && apt-get install -y -qq intel-microcode amd64-microcode" 2>&1; then
            __ok__ "Microcode enabled on ${node_ip}"
            ((success++))
        else
            __warn__ "Failed to enable microcode on ${node_ip}"
            ((failed++))
        fi
    done

    # Enable on local node
    __update__ "Enabling microcode on local node"
    if apt-get update -qq && apt-get install -y -qq intel-microcode amd64-microcode 2>&1; then
        __ok__ "Microcode enabled on local node"
        ((success++))
    else
        __warn__ "Failed to enable microcode on local node"
        ((failed++))
    fi

    echo
    __info__ "Microcode Update Summary:"
    __info__ "  Successful: ${success}"
    [[ $failed -gt 0 ]] && __warn__ "  Failed: ${failed}" || __info__ "  Failed: ${failed}"

    __prompt_keep_installed_packages__

    [[ $failed -gt 0 ]] && exit 1
    __ok__ "Microcode updates enabled on all nodes!"
}

main

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
