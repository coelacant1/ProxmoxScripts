#!/bin/bash
#
# PortScan.sh
#
# Scans TCP ports on Proxmox hosts using nmap.
#
# Usage:
#   PortScan.sh <host> [<host2> ...]
#   PortScan.sh all
#
# Arguments:
#   host - Target host IP or hostname
#   all - Scan all cluster nodes
#
# Examples:
#   PortScan.sh 192.168.1.50
#   PortScan.sh 192.168.1.50 192.168.1.51
#   PortScan.sh all
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

# Note: Variable arguments handled manually (hosts or "all")
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

    __warn__ "Starting port scan on ${#targets[@]} host(s)"
    __warn__ "Use responsibly and only with permission"

    local scanned=0

    for host in "${targets[@]}"; do
        echo
        echo "================================================================"
        __info__ "Scanning: $host"
        echo "================================================================"

        if nmap -p- --open -n "${host}" 2>&1; then
            __ok__ "Scan completed: $host"
            ((scanned += 1))
        else
            __warn__ "Scan failed: $host"
        fi

        echo "================================================================"
    done

    echo
    __ok__ "Port scan completed"
    __info__ "Hosts scanned: $scanned"

    __prompt_keep_installed_packages__
}

main "$@"

###############################################################################
# Script notes:
###############################################################################
# Last checked: 2025-11-20
#
# Changes:
# - 2025-11-20: Updated to use utility functions
# - 2025-11-20: ArgumentParser.sh sourced (hybrid for variable args)
# - 2025-11-20: Pending validation
# - YYYY-MM-DD: Initial creation
#
# Fixes:
# -
#
# Known issues:
# - Pending validation
# -
#

