#!/bin/bash
#
# HostIPerfTest.sh
#
# Automates iperf3 throughput test between two hosts.
#
# Usage:
#   HostIPerfTest.sh <server_host> <client_host> <port>
#
# Arguments:
#   server_host - Host to run iperf3 server (IP or hostname)
#   client_host - Host to run iperf3 client (IP or hostname)
#   port - Port number for iperf3
#
# Examples:
#   HostIPerfTest.sh 192.168.1.10 192.168.1.11 5001
#   HostIPerfTest.sh pve1 pve2 5201
#
# Function Index:
#   - main
#

set -euo pipefail

# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    if [[ $# -lt 3 ]]; then
        __err__ "Missing required arguments"
        echo "Usage: $0 <server_host> <client_host> <port>"
        exit 64
    fi

    local server_host="$1"
    local client_host="$2"
    local port="$3"

    __install_or_prompt__ "iperf3"

    __info__ "Starting iperf3 throughput test"
    __info__ "  Server: $server_host"
    __info__ "  Client: $client_host"
    __info__ "  Port: $port"

    # Kill any existing iperf3 servers
    __update__ "Stopping any existing iperf3 servers on $server_host"
    ssh "root@${server_host}" "pkill -f 'iperf3 -s' 2>/dev/null || true"

    # Start iperf3 server
    __info__ "Starting iperf3 server on $server_host"
    if ssh "root@${server_host}" "iperf3 -s -p '${port}' &" 2>&1; then
        __ok__ "Server started"
    else
        __err__ "Failed to start iperf3 server"
        exit 1
    fi

    __update__ "Waiting 5 seconds for server to be ready"
    sleep 5

    # Run iperf3 client
    __info__ "Running iperf3 client on $client_host"
    echo
    if ssh "root@${client_host}" "iperf3 -c '${server_host}' -p '${port}' -t 10" 2>&1; then
        echo
        __ok__ "Client test completed"
    else
        __warn__ "Client test encountered issues"
    fi

    # Stop iperf3 server
    __update__ "Stopping iperf3 server on $server_host"
    ssh "root@${server_host}" "pkill -f 'iperf3 -s' 2>/dev/null || true"
    __ok__ "Server stopped"

    echo
    __ok__ "Iperf test completed successfully!"

    __prompt_keep_installed_packages__
}

main "$@"

# Testing status:
#   - Updated to use utility functions
#   - Pending validation
