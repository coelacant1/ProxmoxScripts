#!/bin/bash
#
# UplinkSpeedTest.sh
#
# A script to check internet speed on a Proxmox node (local)
# or sequentially across all nodes in the cluster, then report the results.
#
# Usage:
#   UplinkSpeedTest.sh [all|<node1> <node2> ...]
#
# Examples:
#   # Run speed test on the local node
#   UplinkSpeedTest.sh
#
#   # Run speed test on all nodes in the cluster
#   UplinkSpeedTest.sh all
#
#   # Run speed test on specific remote nodes (by name or IP)
#   UplinkSpeedTest.sh pve02 172.20.83.23
#
# This script requires:
#   - 'speedtest' (or 'speedtest-cli') on each node
#   - 'ssh' access to remote nodes (root@<IP>)
#   - A Proxmox environment (pvecm, etc.) if using cluster features
#
# Function Index:
#   - run_speedtest_on_node
#   - resolve_node_argument_to_ip
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

# --- run_speedtest_on_node --------------------------------------------------
run_speedtest_on_node() {
    local node_ip="$1"
    local local_node_ip="$2"

    if [[ "$node_ip" == "$local_node_ip" ]]; then
        __info__ "Running speed test locally on IP: $node_ip"
        speedtest-cli
    else
        __info__ "Running speed test on remote node with IP: $node_ip"
        ssh "root@${node_ip}" "speedtest-cli"
    fi
}

# --- resolve_node_argument_to_ip ---------------------------------------------
resolve_node_argument_to_ip() {
    local arg="$1"

    # Simple check if arg looks like an IPv4 address
    if [[ "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$arg"
    else
        # Attempt to resolve name -> IP
        __get_ip_from_name__ "$arg"
    fi
}

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    # Check for help flag
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        echo "Usage: $0 [all|<node1> <node2> ...]"
        echo
        echo "Examples:"
        echo "  # Test speed locally only"
        echo "  $0"
        echo
        echo "  # Test speed on all nodes in the cluster"
        echo "  $0 all"
        echo
        echo "  # Test speed on specific nodes (by name or IP)"
        echo "  $0 pve02 172.20.83.23"
        exit 0
    fi

    __install_or_prompt__ "speedtest-cli"

    local local_node_name
    local_node_name="$(hostname)"

    # If no arguments, test speed on local node only
    if [[ $# -eq 0 ]]; then
        __init_node_mappings__
        local local_node_ip
        local_node_ip="$(__get_ip_from_name__ "$local_node_name")"

        run_speedtest_on_node "$local_node_ip" "$local_node_ip"
        __prompt_keep_installed_packages__
        exit 0
    fi

    # If "all" was specified, run on local + remote cluster nodes
    if [[ "$1" == "all" ]]; then
        __check_cluster_membership__
        __init_node_mappings__

        local local_node_ip
        local_node_ip="$(__get_ip_from_name__ "$local_node_name")"

        # Run local test first
        __info__ "Running speed test on local node..."
        run_speedtest_on_node "$local_node_ip" "$local_node_ip"
        echo "-----------------------------------------------------"

        # Then run on remote nodes
        __info__ "Gathering remote node IPs..."
        local -a remote_nodes
        mapfile -t remote_nodes < <(__get_remote_node_ips__)

        for node_ip in "${remote_nodes[@]}"; do
            run_speedtest_on_node "$node_ip" "$local_node_ip"
            echo "-----------------------------------------------------"
        done

        __prompt_keep_installed_packages__
        exit 0
    fi

    # Otherwise, treat each argument as a node name or IP
    __init_node_mappings__
    local local_node_ip
    local_node_ip="$(__get_ip_from_name__ "$local_node_name")"

    for arg in "$@"; do
        local node_ip
        node_ip="$(resolve_node_argument_to_ip "$arg")"
        run_speedtest_on_node "$node_ip" "$local_node_ip"
        echo "-----------------------------------------------------"
    done

    __prompt_keep_installed_packages__
}

main "$@"

# Testing status:
#   - Updated to use utility functions and ArgumentParser standards
#   - Pending validation
