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
#   AddNodes.sh 172.20.120.65 172.20.120.66 172.20.120.67
#   AddNodes.sh 172.20.120.65 172.20.120.66 172.20.120.67 --link1 10.10.10.66 10.10.10.67
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

    if [[ $# -lt 2 ]]; then
        __err__ "Missing required arguments"
        echo "Usage: $0 <cluster_ip> <new_node_1> [<new_node_2> ...] [--link1 <link1_1> ...]"
        exit 64
    fi

    local cluster_ip="$1"
    shift

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
        for ((i=0; i<${#nodes[@]}; i++)); do
            link1+=("$1")
            shift
        done
    fi

    __info__ "Adding ${#nodes[@]} node(s) to cluster at ${cluster_ip}"

    local counter=0
    local failed=0

    for node_ip in "${nodes[@]}"; do
        __update__ "Adding node ${node_ip} ($((counter + 1))/${#nodes[@]})"

        local cmd="pvecm add \"${cluster_ip}\" --link0 \"${node_ip}\""
        if $use_link1; then
            cmd+=" --link1 \"${link1[$counter]}\""
            __info__ "  Using link1: ${link1[$counter]}"
        fi

        if ssh -t -o StrictHostKeyChecking=no "root@${node_ip}" "$cmd" 2>&1; then
            __ok__ "Node ${node_ip} added successfully"
        else
            __warn__ "Failed to add node ${node_ip}"
            ((failed++))
        fi

        ((counter++))
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

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
