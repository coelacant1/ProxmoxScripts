#!/bin/bash
#
# PenetrationTest.sh
#
# Conducts basic vulnerability assessment on Proxmox hosts using nmap.
#
# Usage:
#   PenetrationTest.sh <host> [<host2> ...]
#   PenetrationTest.sh all
#
# Arguments:
#   host - Target host IP or hostname
#   all - Test all cluster nodes
#
# Examples:
#   PenetrationTest.sh 192.168.1.50
#   PenetrationTest.sh 192.168.1.50 192.168.1.51
#   PenetrationTest.sh all
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
# shellcheck source=Utilities/Cluster.sh
source "${UTILITYPATH}/Cluster.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# Hybrid parsing: "all" or variable hosts
if [[ $# -lt 1 ]]; then
    __err__ "Missing required argument"
    echo "Usage: $0 <host> [<host2> ...] | all"
    exit 64
fi

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __install_or_prompt__ "nmap"

    local -a targets

    if [[ "$1" == "all" ]]; then
        __check_cluster_membership__

        __info__ "Discovering cluster nodes"
        mapfile -t targets < <(__get_remote_node_ips__)

        if [[ ${#targets[@]} -eq 0 ]]; then
            __err__ "No cluster nodes discovered"
            exit 1
        fi

        __ok__ "Found ${#targets[@]} cluster node(s)"
        for ip in "${targets[@]}"; do
            echo "  - $ip"
        done
        echo
    else
        targets=("$@")
    fi

    __warn__ "Starting vulnerability scan on ${#targets[@]} host(s)"
    __warn__ "Use responsibly and only with explicit permission"
    __warn__ "Unauthorized pentesting is illegal"

    local scanned=0

    for host in "${targets[@]}"; do
        echo
        echo "================================================================"
        __info__ "Scanning: $host"
        echo "================================================================"

        if nmap -sV --script vuln "$host" 2>&1; then
            __ok__ "Scan completed: $host"
            ((scanned++))
        else
            __warn__ "Scan failed: $host"
        fi

        echo "================================================================"
    done

    echo
    __ok__ "Vulnerability scan completed"
    __info__ "Hosts scanned: $scanned"

    __prompt_keep_installed_packages__
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Pending validation


# Testing status:
#   - ArgumentParser.sh sourced (hybrid for "all" or variable hosts)
#   - Pending validation
