#!/bin/bash
#
# AddNodes.sh
#
# Adds multiple nodes to an existing Proxmox cluster.
# Run this script on an existing cluster node.
#
# Usage:
#   AddNodes.sh <cluster_ip> <new_node_1> [<new_node_2> ...] [--link1 <link1_1> [<link1_2> ...]]
#
# Arguments:
#   cluster_ip - Main IP of the cluster to join
#   new_node_* - One or more new node IPs to add
#   --link1    - Optional second link addresses (must match node count)
#
# Examples:
#   AddNodes.sh 192.168.1.65 192.168.1.66 192.168.1.67
#   AddNodes.sh 192.168.1.65 192.168.1.66 192.168.1.67 --link1 10.10.10.66 10.10.10.67
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Custom parsing for this script due to complex variable args with --link1
if [[ $# -lt 2 ]]; then
    __err__ "Missing required arguments"
    echo "Usage: $0 <cluster_ip> <new_node_1> [<new_node_2> ...] [--link1 <link1_1> [<link1_2> ...]]"
    exit 64
fi

CLUSTER_IP="$1"
shift

# Validate cluster IP
if ! [[ "$CLUSTER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    __err__ "Invalid cluster IP: $CLUSTER_IP"
    exit 64
fi

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__
    __check_cluster_membership__

    local -a nodes=()
    local use_link1=false
    local -a link1=()

    # Parse nodes and link1 addresses
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --link1)
                use_link1=true
                shift
                break
                ;;
            *)
                nodes+=("$1")
                shift
                ;;
        esac
    done

    if $use_link1; then
        if [[ $# -lt ${#nodes[@]} ]]; then
            __err__ "Not enough link1 addresses for ${#nodes[@]} node(s)"
            exit 1
        fi
        for ((i = 0; i < ${#nodes[@]}; i++)); do
            link1+=("$1")
            shift
        done
    fi

    __info__ "Adding ${#nodes[@]} node(s) to cluster at ${CLUSTER_IP}"

    local counter=0
    local failed=0

    for node_ip in "${nodes[@]}"; do
        __update__ "Adding node ${node_ip} ($((counter + 1))/${#nodes[@]})"

        local cmd="pvecm add \"${CLUSTER_IP}\""
        if $use_link1; then
            cmd+=" --link0 \"${node_ip}\" --link1 \"${link1[$counter]}\""
            __info__ "  Using link0: ${node_ip}, link1: ${link1[$counter]}"
        else
            cmd+=" --link0 \"${node_ip}\""
        fi

        if ssh -t -o StrictHostKeyChecking=no "root@${node_ip}" "$cmd" 2>&1; then
            __ok__ "Node ${node_ip} added successfully"
        else
            __warn__ "Failed to add node ${node_ip}"
            ((failed += 1))
        fi

        ((counter += 1))
    done

    echo
    if [[ $failed -gt 0 ]]; then
        __warn__ "Added $((counter - failed)) of ${counter} nodes (${failed} failed)"
    else
        __ok__ "All ${counter} nodes added successfully!"
    fi

    __info__ "Verify with: pvecm status"
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: Updated to use ArgumentParser.sh (hybrid for complex args)
# - 2025-11-20: Pending validation
#
# Fixes:
# - 2025-11-19: Fixed link parameter ordering
#
# Known issues:
# -
#

