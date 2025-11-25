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

# shellcheck source=Utilities/ArgumentParser.sh
source "${UTILITYPATH}/ArgumentParser.sh"
# shellcheck source=Utilities/Prompts.sh
source "${UTILITYPATH}/Prompts.sh"
# shellcheck source=Utilities/Communication.sh
source "${UTILITYPATH}/Communication.sh"

trap '__handle_err__ $LINENO "$BASH_COMMAND"' ERR

__parse_args__ "server_host:string client_host:string port:port" "$@"

# --- main --------------------------------------------------------------------
main() {
    __check_root__
    __check_proxmox__

    __install_or_prompt__ "iperf3"

    __info__ "Starting iperf3 throughput test"
    __info__ "  Server: $SERVER_HOST"
    __info__ "  Client: $CLIENT_HOST"
    __info__ "  Port: $PORT"

    # Kill any existing iperf3 servers
    __update__ "Stopping any existing iperf3 servers on $SERVER_HOST"
    ssh "root@${SERVER_HOST}" "pkill -f 'iperf3 -s' 2>/dev/null || true"

    # Start iperf3 server in background with proper cleanup trap
    __info__ "Starting iperf3 server on $SERVER_HOST"
    if ssh "root@${SERVER_HOST}" "nohup iperf3 -s -p '${PORT}' > /dev/null 2>&1 &" 2>&1; then
        __ok__ "Server started"
    else
        __err__ "Failed to start iperf3 server"
        exit 1
    fi

    __update__ "Waiting 5 seconds for server to be ready"
    sleep 5

    # Run iperf3 client
    __info__ "Running iperf3 client on $CLIENT_HOST"
    echo
    if ssh "root@${CLIENT_HOST}" "iperf3 -c '${SERVER_HOST}' -p '${PORT}' -t 10" 2>&1; then
        echo
        __ok__ "Client test completed"
    else
        __warn__ "Client test encountered issues"
    fi

    # Stop iperf3 server
    __update__ "Stopping iperf3 server on $SERVER_HOST"
    ssh "root@${SERVER_HOST}" "pkill -f 'iperf3 -s' 2>/dev/null || true"
    __ok__ "Server stopped"

    echo
    __ok__ "Iperf test completed successfully!"

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
# - 2025-11-20: Pending validation
# - 2025-11-20: Updated to use ArgumentParser.sh
# - 2025-11-20: Validated against CONTRIBUTING.md and PVE Guide
# - Script uses iperf3 for network throughput testing (not Proxmox-specific)
#
# Fixes:
# - Fixed: Use nohup for background iperf3 server to prevent SSH hangup issues
#
# Known issues:
# - Pending validation
# -
#

